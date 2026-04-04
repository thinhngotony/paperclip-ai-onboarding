#!/usr/bin/env bash
# Print a CEO bootstrap invite (authenticated mode). Requires running stack + existing config.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib/access-hint.sh
. "$ROOT/scripts/lib/access-hint.sh"

COMPOSE_FILE="${COMPOSE_FILE:-$ROOT/docker-compose.yml}"
if [[ "${1:-}" == "--force" ]]; then
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" exec -T server \
    sh -c 'cd /app && pnpm paperclipai auth bootstrap-ceo --force'
else
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" exec -T server \
    sh -c 'cd /app && pnpm paperclipai auth bootstrap-ceo'
fi

port="$(grep -E '^PAPERCLIP_PORT=' "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r')"
port="${port:-3100}"
print_remote_access_hint "$port"
