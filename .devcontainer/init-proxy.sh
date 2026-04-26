#!/usr/bin/env bash
# Devcontainer network hardening + proxy sanity-check.
#
# This replaces the domain-filtering portion of the reference init-firewall.sh.
# Instead of maintaining an ipset of IPs inside this container, all HTTP(S)
# egress is forced through the Squid service on the `internal` Docker network,
# which performs domain-based filtering against
# /etc/squid/lists/allowed-domains.txt. This script:
#
#   1. Confirms the Squid proxy is reachable on squid:3128.
#   2. (Defense-in-depth) Installs iptables rules that reject any outbound
#      traffic that isn't going to Squid, DNS, or loopback. This means that
#      even tools that ignore HTTP_PROXY cannot bypass the filter.
#   3. Verifies that an allowed host is reachable via the proxy and that a
#      disallowed host is blocked by the proxy.
#
# Required capabilities: NET_ADMIN, NET_RAW (granted by devcontainer.json).
#
# References:
#   https://code.claude.com/docs/en/devcontainer
#   https://github.com/anthropics/claude-code/tree/main/.devcontainer

set -euo pipefail

PROXY_HOST="${PROXY_HOST:-squid}"
PROXY_PORT="${PROXY_PORT:-3128}"

log() { printf '[init-proxy] %s\n' "$*"; }
die() { printf '[init-proxy][ERROR] %s\n' "$*" >&2; exit 1; }

# --- 1. Proxy reachability ------------------------------------------------

# NOTE on PROXY_IP stability: this script resolves squid -> IP exactly once
# at boot and pins it into an iptables ACCEPT rule below. Docker's embedded
# DNS gives compose services stable IPs for the lifetime of the user-defined
# network, so under normal `docker compose up/start/restart` cycles this is
# fine. If the squid CONTAINER is recreated (e.g. `docker compose up
# --force-recreate squid`) without also restarting the dev container, the
# new squid IP won't match this rule and outbound to squid will be blocked.
# Workaround: restart the dev container too (postStartCommand re-runs).
log "resolving proxy host '${PROXY_HOST}'..."
PROXY_IP="$(getent hosts "${PROXY_HOST}" | awk '{print $1}' | head -n1 || true)"
[[ -n "${PROXY_IP}" ]] || die "cannot resolve ${PROXY_HOST} (is the squid service running?)"
log "proxy resolved: ${PROXY_HOST} -> ${PROXY_IP}:${PROXY_PORT}"

if ! (exec 3<>"/dev/tcp/${PROXY_HOST}/${PROXY_PORT}") 2>/dev/null; then
  die "proxy ${PROXY_HOST}:${PROXY_PORT} is not accepting connections"
fi
log "proxy is accepting connections"

# --- 2. iptables defense-in-depth ----------------------------------------
# The internal docker network already has no NAT to the outside, but we still
# lock down egress so any accidental extra network attachment can't leak.
#
# We use `iptables-restore` to apply the entire ruleset atomically. The old
# approach (iptables -F + iptables -A ...) had a window where the policy
# was DROP but no allow rules existed yet — if the script died mid-way the
# container ended up totally networkless.

# Resolve optional sibling services on the internal docker network so the
# Go app inside the dev container can reach its dependencies (postgres,
# redis) directly without going through Squid. Resolution is best-effort:
# if a service isn't running, we skip it silently — the iptables policy
# still defaults to DROP.
SIBLING_RULES=""
for svc in postgres redis; do
  svc_ip="$(getent hosts "${svc}" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  if [[ -n "${svc_ip}" ]]; then
    log "allowing egress to ${svc} (${svc_ip})"
    SIBLING_RULES+="-A OUTPUT -d ${svc_ip} -j ACCEPT"$'\n'
  fi
done

if command -v iptables-restore >/dev/null 2>&1; then
  log "applying iptables egress restrictions (atomic via iptables-restore)"

  iptables-restore <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT DROP [0:0]
-A OUTPUT -o lo -j ACCEPT
-A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -d ${PROXY_IP} -p tcp --dport ${PROXY_PORT} -j ACCEPT
${SIBLING_RULES}COMMIT
EOF
  log "iptables OUTPUT policy is now DROP with explicit allows"
else
  log "iptables-restore not available; relying on docker internal network only"
fi

# --- 2b. ip6tables: blanket-deny outbound IPv6 ---------------------------
# We don't currently enable IPv6 on the docker networks, but if it ever
# gets turned on (daemon.json `ipv6: true`), all the v4 rules above would
# be silently bypassable via v6. A blanket DROP closes that hole.
if command -v ip6tables-restore >/dev/null 2>&1; then
  log "blanket-denying IPv6 egress"
  ip6tables-restore <<EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT DROP [0:0]
-A OUTPUT -o lo -j ACCEPT
COMMIT
EOF
fi

# --- 3. Verification -----------------------------------------------------

log "verifying proxy filter..."

# Pick an allowed target that is almost always in the allowlist.
if curl --silent --show-error --max-time 10 \
     --proxy "http://${PROXY_HOST}:${PROXY_PORT}" \
     -o /dev/null -w '%{http_code}' \
     https://api.github.com/zen | grep -q '^2'; then
  log "  OK: https://api.github.com reachable via proxy"
else
  log "  WARN: https://api.github.com not reachable via proxy (check allowed-domains.txt)"
fi

# Pick a target that should NOT be in the allowlist.
deny_code="$(curl --silent --max-time 10 \
              --proxy "http://${PROXY_HOST}:${PROXY_PORT}" \
              -o /dev/null -w '%{http_code}' \
              https://example.com || true)"
if [[ "${deny_code}" == "403" || "${deny_code}" == "000" ]]; then
  log "  OK: https://example.com correctly blocked (HTTP ${deny_code})"
else
  log "  WARN: https://example.com returned HTTP ${deny_code} (expected 403)"
fi

log "devcontainer proxy ready. HTTP_PROXY=http://${PROXY_HOST}:${PROXY_PORT}"
log "edit .devcontainer/squid/lists/allowed-domains.txt to update the filter (auto-reloads via inotify; or run reload-squid.sh)"
