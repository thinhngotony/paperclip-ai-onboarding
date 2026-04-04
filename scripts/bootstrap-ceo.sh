#!/usr/bin/env bash
# Rotate / print CEO bootstrap invite and refresh START_HERE.txt
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib/vps-env.sh
. "$ROOT/scripts/lib/vps-env.sh"
# shellcheck source=lib/finalize-invite.sh
. "$ROOT/scripts/lib/finalize-invite.sh"
# shellcheck source=lib/access-hint.sh
. "$ROOT/scripts/lib/access-hint.sh"

COMPOSE_FILE="${COMPOSE_FILE:-$ROOT/docker-compose.yml}"
ilog="$(mktemp)"
set +e
if [[ "${1:-}" == "--force" ]]; then
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" exec -T server \
    sh -c 'cd /app && pnpm paperclipai auth bootstrap-ceo --force' 2>&1 | tee "$ilog"
else
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" exec -T server \
    sh -c 'cd /app && pnpm paperclipai auth bootstrap-ceo' 2>&1 | tee "$ilog"
fi
set -e

port="$(env_get "$ROOT/.env" PAPERCLIP_PORT)"
port="${port:-3100}"
pub="$(env_get "$ROOT/.env" PAPERCLIP_PUBLIC_URL)"
[[ -z "$pub" ]] && pub="http://127.0.0.1:${port}"

refresh_start_here_from_log "$ROOT" "$ilog" "$pub" || true
rm -f "$ilog"

print_remote_access_hint "$port" "$pub"
