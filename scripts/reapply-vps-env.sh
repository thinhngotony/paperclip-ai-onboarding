#!/usr/bin/env bash
# Recompute PAPERCLIP_PUBLIC_URL + PAPERCLIP_ALLOWED_HOSTNAMES from .env and recreate the server container.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=lib/vps-env.sh
. "$ROOT/scripts/lib/vps-env.sh"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT/docker-compose.yml}"
sync_vps_env_file "$ROOT"
docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" up -d --no-deps --force-recreate server
echo "Updated .env and recreated server. Public base: ${VPS_PUBLIC_URL:-}"
