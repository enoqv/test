#!/usr/bin/env bash
# Squid entrypoint with hot-reload on allowed-domains.txt changes.
#
# 1. Starts `squid` in the foreground as PID 1 surrogate.
# 2. Runs an inotify watcher in the background. When /etc/squid/allowed-domains.txt
#    is modified (bind-mounted from the host), the watcher invokes
#    `squid -k reconfigure`, which re-reads the ACL file without dropping
#    existing client connections.

set -euo pipefail

ALLOWLIST="/etc/squid/allowed-domains.txt"
SQUID_CONF="/etc/squid/squid.conf"

log() { printf '[squid-entrypoint] %s\n' "$*"; }

# The squid process drops privileges to the `proxy` user. Volume-mounted
# log/cache dirs come up owned by root, so fix ownership before starting.
for d in /var/log/squid /var/spool/squid /var/cache/squid; do
  [[ -d "$d" ]] || mkdir -p "$d"
  chown -R proxy:proxy "$d" 2>/dev/null || true
done

# Validate the config up-front so we fail fast with a readable error rather
# than getting stuck in a healthcheck loop.
log "parsing squid config"
if ! squid -k parse -f "${SQUID_CONF}"; then
  log "ERROR: squid config failed to parse; aborting"
  exit 1
fi

# Warm up the cache dirs if they don't exist yet.
if [[ ! -d /var/spool/squid/00 ]]; then
  log "initializing squid cache directories"
  squid -N -z -f "${SQUID_CONF}" || true
fi

log "starting squid in foreground"
# `-N` keeps squid in the foreground; `-Y` ignores client requests during
# reconfigure; default config path is /etc/squid/squid.conf.
squid -N -Y -f "${SQUID_CONF}" &
SQUID_PID=$!

reload_squid() {
  if kill -0 "${SQUID_PID}" 2>/dev/null; then
    log "reloading squid (allowlist changed)"
    # `squid -k reconfigure` sends SIGHUP to the running master; it re-reads
    # ACL files including /etc/squid/allowed-domains.txt.
    squid -k reconfigure -f "${SQUID_CONF}" || log "reconfigure failed"
  fi
}

# Forward termination signals to squid.
trap 'log "stopping squid"; squid -k shutdown -f "${SQUID_CONF}" || true; wait "${SQUID_PID}" 2>/dev/null || true; exit 0' TERM INT

# inotify watcher. We watch the parent directory because some editors
# replace the file (write-to-temp + rename) rather than modifying in place,
# which invalidates a watch placed directly on the file.
if command -v inotifywait >/dev/null 2>&1 && [[ -e "${ALLOWLIST}" ]]; then
  log "watching ${ALLOWLIST} for changes"
  (
    while true; do
      inotifywait -qq -e close_write,move,create,delete \
        "$(dirname "${ALLOWLIST}")" 2>/dev/null || sleep 2
      # Debounce: collapse multiple rapid changes into one reconfigure.
      sleep 1
      reload_squid
    done
  ) &
fi

# Block on squid so the container exits if squid exits.
wait "${SQUID_PID}"
