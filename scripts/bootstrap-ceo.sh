#!/usr/bin/env bash
# Print a CEO bootstrap invite (authenticated mode). Requires running stack + existing config.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT/docker-compose.yml}"
if [[ "${1:-}" == "--force" ]]; then
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" exec -T server \
    sh -c 'cd /app && pnpm paperclipai auth bootstrap-ceo --force'
else
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" exec -T server \
    sh -c 'cd /app && pnpm paperclipai auth bootstrap-ceo'
fi
