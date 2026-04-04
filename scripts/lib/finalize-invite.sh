#!/usr/bin/env bash
# shellcheck shell=bash
# End-of-setup summary: health check, CEO invite URL, START_HERE.txt

strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

extract_invite_from_log() {
  strip_ansi <"$1" | grep -oE 'https?://[^[:space:]]+/invite/pcp_bootstrap_[a-fA-F0-9]+' | head -1
}

extract_expires_from_log() {
  strip_ansi <"$1" | grep -i 'expires' | head -1 | sed 's/.*[Ee]xpires:[[:space:]]*//' | tr -d '\r'
}

write_start_here_ready() {
  local root_dir="$1"
  local pub="$2"
  local f="$root_dir/START_HERE.txt"
  cat >"$f" <<EOF
Paperclip — instance is ready

Sign in:
  ${pub}

(Generated $(date -Iseconds))
EOF
}

write_start_here_pending() {
  local root_dir="$1"
  local invite="$2"
  local expires="$3"
  local pub="$4"
  local f="$root_dir/START_HERE.txt"
  {
    echo "Paperclip — finish setup (first admin)"
    echo ""
    echo "STEP 1 — Open this invite link once in your browser:"
    echo "  ${invite}"
    echo ""
    if [[ -n "$expires" ]]; then
      echo "Invite expires: ${expires}"
      echo ""
    fi
    echo "STEP 2 — Then use Paperclip here:"
    echo "  ${pub}"
    echo ""
    echo "If the link expired, on the server run:"
    echo "  ./scripts/bootstrap-ceo.sh --force"
    echo ""
    echo "(Generated $(date -Iseconds))"
  } >"$f"
}

print_banner_ready() {
  local pub="$1"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Paperclip is ready — sign in at:"
  echo "    ${pub}"
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Also saved: START_HERE.txt"
  echo ""
}

print_banner_pending() {
  local invite="$1"
  local expires="$2"
  local pub="$3"
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  NEXT STEP — Create the first admin (open in your browser):"
  echo ""
  echo "    ${invite}"
  echo ""
  [[ -n "$expires" ]] && echo "  Invite expires: ${expires}" && echo ""
  echo "  After that, use Paperclip at:"
  echo "    ${pub}"
  echo "═══════════════════════════════════════════════════════════════════"
  echo "  Saved to: START_HERE.txt"
  echo ""
}

# Args: root_dir compose_file env_file port public_url
emit_post_setup_summary() {
  local root_dir="$1"
  local compose_file="$2"
  local env_file="$3"
  local port="${4:-3100}"
  local pub="${5:-http://127.0.0.1:${port}}"

  local health=""
  health="$(curl -sfS --max-time 10 "http://127.0.0.1:${port}/api/health")" || true

  if [[ -n "$health" ]] && echo "$health" | grep -q '"bootstrapStatus":"ready"'; then
    write_start_here_ready "$root_dir" "$pub"
    print_banner_ready "$pub"
    return 0
  fi

  local ilog
  ilog="$(mktemp)"
  set +e
  docker compose -f "$compose_file" --env-file "$env_file" exec -T server \
    sh -c 'cd /app && pnpm paperclipai auth bootstrap-ceo' >"$ilog" 2>&1
  local rc=$?
  set -e

  if strip_ansi <"$ilog" | grep -q 'already has an admin user'; then
    rm -f "$ilog"
    write_start_here_ready "$root_dir" "$pub"
    print_banner_ready "$pub"
    return 0
  fi

  if [[ $rc -ne 0 ]]; then
    echo "Could not run bootstrap-ceo (exit $rc). See log below or run ./scripts/bootstrap-ceo.sh --force" >&2
    cat "$ilog" >&2
    rm -f "$ilog"
    write_start_here_pending "$root_dir" "(run: ./scripts/bootstrap-ceo.sh --force)" "" "$pub"
    return "$rc"
  fi

  local invite expires
  invite="$(extract_invite_from_log "$ilog")"
  expires="$(extract_expires_from_log "$ilog")"
  rm -f "$ilog"

  if [[ -z "$invite" ]]; then
    echo "Warning: could not parse invite URL from CLI output. Run: ./scripts/bootstrap-ceo.sh --force" >&2
    write_start_here_pending "$root_dir" "(run: ./scripts/bootstrap-ceo.sh --force)" "" "$pub"
    return 1
  fi

  write_start_here_pending "$root_dir" "$invite" "$expires" "$pub"
  print_banner_pending "$invite" "$expires" "$pub"
  return 0
}

# After bootstrap-ceo was run and output saved to a log file.
refresh_start_here_from_log() {
  local root_dir="$1"
  local ilog="$2"
  local pub="$3"
  if strip_ansi <"$ilog" | grep -q 'already has an admin user'; then
    write_start_here_ready "$root_dir" "$pub"
    print_banner_ready "$pub"
    return 0
  fi
  local invite expires
  invite="$(extract_invite_from_log "$ilog")"
  expires="$(extract_expires_from_log "$ilog")"
  if [[ -n "$invite" ]]; then
    write_start_here_pending "$root_dir" "$invite" "$expires" "$pub"
    print_banner_pending "$invite" "$expires" "$pub"
    return 0
  fi
  echo "Could not parse invite URL from CLI output. See messages above." >&2
  return 1
}
