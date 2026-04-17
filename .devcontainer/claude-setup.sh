#!/usr/bin/env bash
# Pre-install Claude Code MCP servers, plugin marketplaces, plugins, and
# skills declared under .devcontainer/claude/. Invoked by the
# devcontainer.json postCreateCommand; idempotent (safe to rerun).
#
# Declarative inputs (all optional):
#   .devcontainer/claude/mcp-servers.json   Object keyed by server name;
#                                           values are the MCP config blob
#                                           (same shape as `claude mcp
#                                           add-json <name> '<json>'`).
#   .devcontainer/claude/marketplaces.txt   One plugin-marketplace URL per
#                                           line (# comments allowed).
#   .devcontainer/claude/plugins.txt        One `plugin@marketplace` spec
#                                           per line.
#   .devcontainer/claude/skills/<name>/     Skill directories copied into
#                                           $CLAUDE_CONFIG_DIR/skills/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_DIR="${SCRIPT_DIR}/claude"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"

log() { printf '[claude-setup] %s\n' "$*"; }

if ! command -v claude >/dev/null 2>&1; then
  log "claude binary not on PATH; skipping preinstall"
  exit 0
fi

if [ ! -d "${CONF_DIR}" ]; then
  log "no ${CONF_DIR}; nothing to pre-install"
  exit 0
fi

mkdir -p "${CLAUDE_HOME}"

# --- MCP servers ------------------------------------------------------
MCP_FILE="${CONF_DIR}/mcp-servers.json"
if [ -s "${MCP_FILE}" ] && jq -e 'type == "object" and length > 0' "${MCP_FILE}" >/dev/null 2>&1; then
  while IFS= read -r entry; do
    name="$(printf '%s' "${entry}" | base64 -d | jq -r '.key')"
    cfg="$(printf '%s'  "${entry}" | base64 -d | jq -c '.value')"
    log "installing MCP server: ${name}"
    claude mcp remove "${name}" --scope user >/dev/null 2>&1 || true
    claude mcp add-json "${name}" "${cfg}" --scope user
  done < <(jq -r 'to_entries[] | @base64' "${MCP_FILE}")
fi

# --- Plugin marketplaces ----------------------------------------------
MARKET_FILE="${CONF_DIR}/marketplaces.txt"
if [ -s "${MARKET_FILE}" ]; then
  while IFS= read -r url; do
    [ -z "${url}" ] && continue
    log "adding plugin marketplace: ${url}"
    claude plugin marketplace add "${url}" || log "  failed (skipping): ${url}"
  done < <(grep -vE '^\s*(#|$)' "${MARKET_FILE}" || true)
fi

# --- Plugins ----------------------------------------------------------
PLUGINS_FILE="${CONF_DIR}/plugins.txt"
if [ -s "${PLUGINS_FILE}" ]; then
  while IFS= read -r spec; do
    [ -z "${spec}" ] && continue
    log "installing plugin: ${spec}"
    claude plugin install "${spec}" || log "  failed (skipping): ${spec}"
  done < <(grep -vE '^\s*(#|$)' "${PLUGINS_FILE}" || true)
fi

# --- Skills -----------------------------------------------------------
SKILLS_DIR="${CONF_DIR}/skills"
if [ -d "${SKILLS_DIR}" ] && [ -n "$(ls -A "${SKILLS_DIR}" 2>/dev/null || true)" ]; then
  mkdir -p "${CLAUDE_HOME}/skills"
  cp -rT "${SKILLS_DIR}" "${CLAUDE_HOME}/skills"
  log "synced skills into ${CLAUDE_HOME}/skills"
fi

log "done"
