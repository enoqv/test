#!/usr/bin/env bash
# Force the squid container to re-read its allowlist.
#
# Normally this is automatic: the squid service watches
# /etc/squid/allowed-domains.txt with inotify and runs `squid -k reconfigure`
# whenever the file changes. If something went wrong (or the file was edited
# in a way inotify missed), this script pokes the file by updating its mtime,
# which triggers the same reconfigure path.
#
# Usage (from inside the dev container):
#   sudo reload-squid.sh

set -euo pipefail

ALLOWLIST="/etc/squid/allowed-domains.txt"

log() { printf '[reload-squid] %s\n' "$*"; }

if [[ ! -e "${ALLOWLIST}" ]]; then
  echo "[reload-squid] error: ${ALLOWLIST} not found inside dev container" >&2
  exit 1
fi

log "touching ${ALLOWLIST} to trigger squid reconfigure"
# The file is bind-mounted read-only here but readable; we need to modify it
# on the host. `touch -c` won't work through a read-only mount, so we write
# through the workspace copy, which is the same inode on the host side.
WORKSPACE_COPY="/workspace/.devcontainer/squid/allowed-domains.txt"
if [[ -w "${WORKSPACE_COPY}" ]]; then
  touch "${WORKSPACE_COPY}"
  log "reload requested via ${WORKSPACE_COPY} (inotify watcher will reconfigure squid)"
else
  echo "[reload-squid] error: ${WORKSPACE_COPY} not writable" >&2
  exit 1
fi

log "tail 'docker logs <squid>' to confirm reconfigure"
