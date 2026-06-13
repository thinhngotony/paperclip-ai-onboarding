#!/usr/bin/env bash
# shellcheck shell=bash
# Detect a local 9Router and sync NINEROUTER_PORT + OPENAI_* (/v1) + ANTHROPIC_* (Claude Code → host 9Router).
# Anthropic path: ANTHROPIC_BASE_URL=http://host.docker.internal:<port> (no /v1 — see 9Router Claude Code docs).
# Requires vps-env.sh (strip_env_keys, append_env_kv, env_get) to be sourced first.

ninerouter_ping() {
  local host="${1:-127.0.0.1}"
  local port="$2"
  curl -sfS --max-time 4 "http://${host}:${port}/v1/models" >/dev/null 2>&1
}

discover_ninerouter_port() {
  local envf="$1"
  local bind
  bind="$(env_get "$envf" NINEROUTER_BIND_HOST)"
  bind="${bind:-127.0.0.1}"
  local try
  try="$(env_get "$envf" NINEROUTER_PORT)"
  if [[ -n "$try" ]] && ninerouter_ping "$bind" "$try"; then
    echo "$try"
    return 0
  fi
  for try in 20128; do
    if ninerouter_ping "$bind" "$try"; then
      echo "$try"
      return 0
    fi
  done
  return 1
}

# First non-empty string field from apiKeys[] in 9Router db.json (dashboard keys).
extract_ninerouter_dashboard_api_key() {
  local db="$1"
  [[ -f "$db" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$db" <<'PY' 2>/dev/null || return 1
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.is_file():
    sys.exit(1)
data = json.loads(p.read_text(encoding="utf-8"))
keys = data.get("apiKeys") or []
for item in keys:
    if not isinstance(item, dict):
        continue
    for field in ("key", "apiKey", "token", "secret", "value"):
        v = item.get(field)
        if isinstance(v, str) and v.strip():
            print(v.strip())
            raise SystemExit(0)
raise SystemExit(1)
PY
}

resolve_ninerouter_db_path() {
  local envf="$1"
  local p
  p="$(env_get "$envf" NINEROUTER_DB_PATH)"
  if [[ -n "$p" ]]; then
    echo "${p/#\~/$HOME}"
    return 0
  fi
  for p in "${HOME}/.9router/db.json" "${HOME}/.local/share/9router/db.json"; do
    if [[ -f "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

# True if .env points at Anthropic’s cloud API (do not overwrite with 9Router).
preserve_direct_anthropic_env() {
  local envf="$1"
  local k b
  k="$(env_get "$envf" ANTHROPIC_API_KEY)"
  b="$(env_get "$envf" ANTHROPIC_BASE_URL)"
  [[ "$k" == sk-ant-* ]] || return 1
  [[ -n "$b" ]] || return 1
  [[ "$b" == *api.anthropic.com* ]] && return 0
  return 1
}

# True if the stored OPENAI_API_KEY value should not be preserved (template / typo).
should_replace_openai_api_key_value() {
  local v="${1//[[:space:]]/}"
  [[ -z "$v" ]] && return 0
  case "$v" in
    OPENAI_API_KEY|YOUR_OPENAI_API_KEY|your-api-key*|changeme|REPLACE*|sk-placeholder*) return 0 ;;
  esac
  return 1
}

# Refresh OpenAI-compatible 9Router settings in .env.
# Args: root_dir [refresh_key=0]
# If refresh_key=1, replace OPENAI_API_KEY even when already set.
sync_9router_llm_env() {
  local root_dir="$1"
  local refresh_key="${2:-0}"
  local envf="$root_dir/.env"
  [[ -f "$envf" ]] || return 1

  local bind
  bind="$(env_get "$envf" NINEROUTER_BIND_HOST)"
  bind="${bind:-127.0.0.1}"

  local port
  if ! port="$(discover_ninerouter_port "$envf")"; then
    echo "Warning: could not reach 9Router at http://${bind}:<port>/v1/models (set NINEROUTER_PORT if non-default)." >&2
    return 1
  fi
  echo "9Router detected on http://${bind}:${port}/v1"

  local base_url="http://${bind}:${port}/v1"
  local anthropic_base
  anthropic_base="$(env_get "$envf" NINEROUTER_ANTHROPIC_BASE_URL)"
  anthropic_base="${anthropic_base:-http://${bind}:${port}}"

  local preserve_anthropic=0
  if preserve_direct_anthropic_env "$envf"; then
    preserve_anthropic=1
    echo "Keeping direct Anthropic API settings (ANTHROPIC_API_KEY sk-ant-* + api.anthropic.com); not overwriting ANTHROPIC_* for 9Router."
  fi

  # Default: do NOT set ANTHROPIC_* for 9Router (Claude CLI has model prefix issues)
  # Users should use Codex Local adapter which works reliably with 9Router
  preserve_anthropic=1
  echo "Skipping ANTHROPIC_* configuration for 9Router (Claude CLI incompatible with model prefixes)."
  echo "Use Codex Local or OpenCode Local adapter in Paperclip instead."

  local key=""
  local existing_openai
  existing_openai="$(env_get "$envf" OPENAI_API_KEY)"

  if [[ "$refresh_key" -eq 0 ]] && [[ -n "$existing_openai" ]] && ! should_replace_openai_api_key_value "$existing_openai"; then
    key="$existing_openai"
    echo "Keeping existing OPENAI_API_KEY from .env (use --refresh-9router-key to replace)."
  else
    key="$(env_get "$envf" NINEROUTER_API_KEY)"
    if [[ -z "$key" ]]; then
      local dbp
      if dbp="$(resolve_ninerouter_db_path "$envf")"; then
        key="$(extract_ninerouter_dashboard_api_key "$dbp" || true)"
        [[ -n "$key" ]] && echo "Using API key from 9Router db: $dbp"
      fi
    else
      echo "Using NINEROUTER_API_KEY from .env for OPENAI_API_KEY."
    fi
    if [[ -z "$key" ]]; then
      key="9router-local"
      echo "Using default OPENAI_API_KEY placeholder (9Router allows unauthenticated /v1 on many installs)."
    fi
  fi

  if [[ "$preserve_anthropic" -eq 1 ]]; then
    strip_env_keys "$envf" NINEROUTER_PORT OPENAI_BASE_URL OPENAI_API_KEY
  else
    strip_env_keys "$envf" NINEROUTER_PORT OPENAI_BASE_URL OPENAI_API_KEY ANTHROPIC_BASE_URL ANTHROPIC_API_KEY
  fi
  append_env_kv "$envf" \
    "NINEROUTER_PORT=${port}" \
    "OPENAI_BASE_URL=${base_url}" \
    "OPENAI_API_KEY=${key}"

  # Note: ANTHROPIC_* not set by default due to Claude CLI model prefix incompatibility
  # Users should use Codex Local or OpenCode Local adapter in Paperclip

  return 0
}
