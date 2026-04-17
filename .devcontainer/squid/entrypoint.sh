#!/usr/bin/env bash
# Squid entrypoint with hot-reload on allowed-domains.txt changes.
#
# 1. Validates the squid config (fails fast with a readable error).
# 2. Fixes ownership on volume-mounted cache/log dirs.
# 3. Starts `squid` in the foreground.
# 4. Runs an inotify watcher in the background. When /etc/squid/allowed-domains.txt
#    is modified (bind-mounted from the host), the watcher invokes
#    `squid -k reconfigure`, which re-reads the ACL file without dropping
#    existing client connections.

set -euo pipefail

ALLOWLIST="/etc/squid/allowed-domains.txt"
SQUID_CONF="/etc/squid/squid.conf"

log() { printf '[squid-entrypoint] %s\n' "$*"; }

log "squid version: $(squid -v 2>&1 | head -n1 || echo unknown)"

# The squid process drops privileges to the `proxy` user. Volume-mounted
# log/cache dirs come up owned by root, so fix ownership before starting.
for d in /var/log/squid /var/spool/squid /var/cache/squid /run/squid; do
  [[ -d "$d" ]] || mkdir -p "$d"
  chown -R proxy:proxy "$d" 2>/dev/null || true
done

# Ensure the allowlist file exists (empty file is valid; squid will deny all).
if [[ ! -f "${ALLOWLIST}" ]]; then
  log "WARN: ${ALLOWLIST} missing, creating empty file"
  : > "${ALLOWLIST}"
fi

# Validate the config up-front so we fail fast with a readable error rather
# than getting stuck in a healthcheck loop.
log "parsing squid config ${SQUID_CONF}"
if ! squid -k parse -f "${SQUID_CONF}" 2>&1; then
  log "ERROR: squid config failed to parse; aborting"
  exit 1
fi

# Initialise cache dirs if they don't already exist.
if [[ ! -d /var/spool/squid/00 ]]; then
  log "initializing squid cache directories (-z)"
  squid -N -z -f "${SQUID_CONF}" 2>&1 || log "cache init returned non-zero (continuing)"
fi

log "starting squid in foreground (-N -Y)"
# `-N` keeps squid in the foreground; `-Y` answers quickly while rebuilding.
squid -N -Y -f "${SQUID_CONF}" &
SQUID_PID=$!

# Stream squid log files to this process's stdout/stderr so that
# `docker logs squid` shows every request and any squid errors. We
# pre-create the files so `tail -F` doesn't race with squid opening them.
: > /var/log/squid/access.log
: > /var/log/squid/cache.log
chown proxy:proxy /var/log/squid/access.log /var/log/squid/cache.log 2>/dev/null || true
tail -F /var/log/squid/access.log 2>/dev/null &
TAIL_ACCESS_PID=$!
tail -F /var/log/squid/cache.log 2>/dev/null &
TAIL_CACHE_PID=$!

reload_squid() {
  if kill -0 "${SQUID_PID}" 2>/dev/null; then
    log "reloading squid (allowlist changed)"
    squid -k reconfigure -f "${SQUID_CONF}" || log "reconfigure failed"
  fi
}

# Forward termination signals to squid + stop the log tailers.
trap 'log "stopping squid"; squid -k shutdown -f "${SQUID_CONF}" 2>/dev/null || true; kill "${TAIL_ACCESS_PID}" "${TAIL_CACHE_PID}" 2>/dev/null || true; wait "${SQUID_PID}" 2>/dev/null || true; exit 0' TERM INT

# inotify watcher — watch the parent directory because editors often replace
# the file via write-to-temp + rename, invalidating direct watches.
if command -v inotifywait >/dev/null 2>&1 && [[ -e "${ALLOWLIST}" ]]; then
  log "watching ${ALLOWLIST} for changes"
  (
    while true; do
      inotifywait -qq -e close_write,move,create,delete \
        "$(dirname "${ALLOWLIST}")" 2>/dev/null || sleep 2
      sleep 1  # debounce
      reload_squid
    done
  ) &
fi

# Block on squid; container exits when squid exits.
wait "${SQUID_PID}"
EXIT=$?
log "squid exited with status ${EXIT}"
exit "${EXIT}"
