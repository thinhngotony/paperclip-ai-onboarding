#!/usr/bin/env bash
# shellcheck shell=bash
# Patch .env for VPS access (public IP / hostname allow-list). Sourced by setup.sh.

detect_public_ipv4() {
  local ip=""
  for url in \
    "https://api.ipify.org" \
    "https://checkip.amazonaws.com" \
    "https://ifconfig.me/ip"; do
    ip="$(curl -4fsS --max-time 6 "$url" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

# host part only, lowercase
parse_http_url_host() {
  local raw="$1"
  raw="${raw#*://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  echo "${raw,,}"
}

is_local_host() {
  case "${1,,}" in
    ""|127.0.0.1|localhost|::1) return 0 ;;
    *) return 1 ;;
  esac
}

# Args after 127.0.0.1 + localhost (e.g. one public IP or domain).
merge_allowed_hostnames() {
  local -A seen
  local out=()
  local h
  for h in 127.0.0.1 localhost "$@"; do
    h="${h,,}"
    h="${h//[[:space:]]/}"
    [[ -z "$h" ]] && continue
    [[ -n "${seen[$h]:-}" ]] && continue
    seen[$h]=1
    out+=("$h")
  done
  (IFS=,; echo "${out[*]}")
}

strip_env_keys() {
  local file="$1"
  shift
  local tmp
  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    local skip=0
    for key in "$@"; do
      if [[ "$line" == "${key}="* ]]; then
        skip=1
        break
      fi
    done
    [[ "$skip" -eq 0 ]] && printf '%s\n' "$line"
  done <"$file" >"$tmp"
  mv "$tmp" "$file"
}

append_env_kv() {
  local file="$1"
  shift
  printf '%s\n' "$@" >>"$file"
}

# Reads root_dir/.env; updates public URL + allowed hostnames for VPS or local profile.
# Exports: VPS_EFFECTIVE_HOST, VPS_PUBLIC_URL
env_get() {
  local envf="$1"
  local key="$2"
  awk -v k="$key" '
    index($0, k "=") == 1 {
      v = substr($0, length(k) + 2)
      sub(/\r$/, "", v)
      print v
      exit
    }
  ' "$envf"
}

sync_vps_env_file() {
  local root_dir="$1"
  local envf="$root_dir/.env"
  [[ -f "$envf" ]] || return 1

  local port profile vps_host_hint public_url_existing
  port="$(env_get "$envf" PAPERCLIP_PORT)"
  port="${port:-3100}"
  profile="$(env_get "$envf" PAPERCLIP_NETWORK_PROFILE)"
  profile="${profile:-vps}"
  profile="${profile,,}"

  vps_host_hint="$(env_get "$envf" PAPERCLIP_VPS_HOST)"
  vps_host_hint="${vps_host_hint//[[:space:]]/}"
  public_url_existing="$(env_get "$envf" PAPERCLIP_PUBLIC_URL)"

  local host public_url allowed

  if [[ "$profile" == "local" ]]; then
    host="127.0.0.1"
    public_url="http://127.0.0.1:${port}"
    allowed="$(merge_allowed_hostnames)"
    VPS_EFFECTIVE_HOST="$host"
    VPS_PUBLIC_URL="$public_url"
  else
    pu=""
    hu=""

    # Explicit full URL (e.g. https://paperclip.example.com) — keep as-is for auth redirects.
    if [[ -n "$public_url_existing" ]]; then
      hu="$(parse_http_url_host "$public_url_existing")"
      if ! is_local_host "$hu"; then
        pu="${public_url_existing%/}"
        allowed="$(merge_allowed_hostnames "$hu")"
        VPS_EFFECTIVE_HOST="$hu"
        VPS_PUBLIC_URL="$pu"
      fi
    fi

    if [[ -z "$pu" ]]; then
      if [[ -n "$vps_host_hint" ]]; then
        hu="${vps_host_hint,,}"
      elif [[ -n "$public_url_existing" ]] && is_local_host "$(parse_http_url_host "$public_url_existing")"; then
        hu=""
      fi

      if [[ -z "$hu" ]] || is_local_host "$hu"; then
        echo "Detecting public IPv4 for Paperclip (override with PAPERCLIP_VPS_HOST=... or PAPERCLIP_PUBLIC_URL=... in .env)..."
        if hu="$(detect_public_ipv4)"; then
          echo "Using public IP: $hu"
        else
          echo "Warning: public IPv4 detection failed. Set PAPERCLIP_VPS_HOST or PAPERCLIP_PUBLIC_URL in .env and re-run ./scripts/setup.sh" >&2
          hu="127.0.0.1"
        fi
      fi

      pu="http://${hu}:${port}"
      allowed="$(merge_allowed_hostnames "$hu")"
      VPS_EFFECTIVE_HOST="$hu"
      VPS_PUBLIC_URL="$pu"
    fi
  fi

  strip_env_keys "$envf" \
    PAPERCLIP_PUBLIC_URL \
    PAPERCLIP_ALLOWED_HOSTNAMES \
    PAPERCLIP_NETWORK_PROFILE

  append_env_kv "$envf" "PAPERCLIP_NETWORK_PROFILE=${profile}"

  if [[ -n "$vps_host_hint" ]]; then
    append_env_kv "$envf" "PAPERCLIP_VPS_HOST=${vps_host_hint}"
  fi

  append_env_kv "$envf" \
    "PAPERCLIP_PUBLIC_URL=${VPS_PUBLIC_URL}" \
    "PAPERCLIP_ALLOWED_HOSTNAMES=${allowed}"

  export VPS_EFFECTIVE_HOST VPS_PUBLIC_URL
}

# Force local-only profile before sync_vps_env_file (used by setup.sh --local).
force_local_network_profile() {
  local root_dir="$1"
  local envf="$root_dir/.env"
  [[ -f "$envf" ]] || return 1
  strip_env_keys "$envf" PAPERCLIP_NETWORK_PROFILE PAPERCLIP_VPS_HOST
  append_env_kv "$envf" "PAPERCLIP_NETWORK_PROFILE=local"
}
