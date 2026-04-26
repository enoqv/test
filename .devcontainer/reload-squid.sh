#!/usr/bin/env bash
# Force the squid container to re-read its allowlist.
#
# Normally this is automatic: the squid container bind-mounts the
# .devcontainer/squid/lists directory and watches it with inotify, running
# `squid -k reconfigure` whenever any file under it changes. This helper is
# only needed if the inotify event was missed for some reason.
#
# Runs as the regular `dever` user — no sudo required, since the workspace
# copy is owned by dever via the bind-mount.
#
# Usage (from inside the dev container):
#   reload-squid.sh

set -euo pipefail

# We touch the workspace copy (writable from dever) rather than the
# bind-mounted RO copy at /etc/squid/lists/. The squid container observes
# the same inode via its own bind-mount.
WORKSPACE_COPY="/workspace/.devcontainer/squid/lists/allowed-domains.txt"

log() { printf '[reload-squid] %s\n' "$*"; }

if [[ ! -e "${WORKSPACE_COPY}" ]]; then
  echo "[reload-squid] error: ${WORKSPACE_COPY} not found" >&2
  exit 1
fi

if [[ ! -w "${WORKSPACE_COPY}" ]]; then
  echo "[reload-squid] error: ${WORKSPACE_COPY} not writable by $(id -un)" >&2
  exit 1
fi

log "touching ${WORKSPACE_COPY} to trigger squid reconfigure"
touch "${WORKSPACE_COPY}"
log "reload requested (inotify watcher in squid container will reconfigure)"
log "tail 'docker logs <squid>' on the host to confirm reconfigure"
