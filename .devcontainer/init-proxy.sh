#!/usr/bin/env bash
# Devcontainer network hardening + proxy sanity-check.
#
# This replaces the domain-filtering portion of the reference init-firewall.sh.
# Instead of maintaining an ipset of IPs inside this container, all HTTP(S)
# egress is forced through the Squid service on the `internal` Docker network,
# which performs domain-based filtering against
# /etc/squid/allowed-domains.txt. This script:
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

if command -v iptables >/dev/null 2>&1; then
  log "applying iptables egress restrictions"

  # Flush existing rules in filter table.
  iptables -F OUTPUT || true
  iptables -P OUTPUT DROP

  # Allow loopback.
  iptables -A OUTPUT -o lo -j ACCEPT

  # Allow DNS (docker embedded resolver lives on 127.0.0.11 usually, but
  # outbound 53 also works for container DNS in some setups).
  iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
  iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

  # Allow established/related (responses to our proxy requests).
  iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

  # Allow traffic to the Squid proxy.
  iptables -A OUTPUT -d "${PROXY_IP}" -p tcp --dport "${PROXY_PORT}" -j ACCEPT

  # Allow reaching docker-compose sibling services (postgres, redis) on the
  # internal network. These are resolved lazily if they exist.
  for svc in postgres redis; do
    svc_ip="$(getent hosts "${svc}" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
    if [[ -n "${svc_ip}" ]]; then
      log "allowing egress to ${svc} (${svc_ip})"
      iptables -A OUTPUT -d "${svc_ip}" -j ACCEPT
    fi
  done

  log "iptables OUTPUT policy is now DROP with explicit allows"
else
  log "iptables not available; relying on docker internal network only"
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
log "edit .devcontainer/squid/allowed-domains.txt then run 'sudo reload-squid.sh' to update the filter"
