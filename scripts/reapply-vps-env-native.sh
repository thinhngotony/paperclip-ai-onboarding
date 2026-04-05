#!/usr/bin/env bash
# Recompute PAPERCLIP_PUBLIC_URL + PAPERCLIP_ALLOWED_HOSTNAMES from .env and restart the native server.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Source helper libraries
# shellcheck source=lib/vps-env.sh
. "$ROOT/scripts/lib/vps-env.sh"

# Re-sync VPS env
sync_vps_env_file "$ROOT"

# Fix Docker-specific hostnames if present
sed -i 's|host\.docker\.internal|127.0.0.1|g' "$ROOT/.env"

# Copy updated env to /etc/paperclip
cp "$ROOT/.env" /etc/paperclip/.env

# Restart the service
systemctl restart paperclip

# Wait for health
port="$(env_get "$ROOT/.env" PAPERCLIP_PORT)"
port="${port:-3100}"
url="http://127.0.0.1:${port}/api/health"

echo "Waiting for Paperclip at $url ..."
for i in $(seq 1 30); do
    if curl -sfS "$url" >/dev/null 2>&1; then
        echo "Paperclip is healthy."
        break
    fi
    sleep 2
done

echo "Updated .env and restarted service. Public base: ${VPS_PUBLIC_URL:-}"