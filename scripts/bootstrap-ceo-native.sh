#!/usr/bin/env bash
# Rotate / print CEO bootstrap invite and refresh START_HERE.txt (native, no Docker)
# Run this while the Paperclip service is running — it connects to the DB via the service.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Source helper libraries
# shellcheck source=lib/vps-env.sh
. "$ROOT/scripts/lib/vps-env.sh"
# shellcheck source=lib/finalize-invite.sh
. "$ROOT/scripts/lib/finalize-invite.sh"
# shellcheck source=lib/access-hint.sh
. "$ROOT/scripts/lib/access-hint.sh"

VENDOR_DIR="${VENDOR_DIR:-/opt/paperclip-ai-onboarding/vendor/paperclip}"
PAPERCLIP_SVC_HOME="/var/lib/paperclip"
PAPERCLIP_CONFIG="${PAPERCLIP_SVC_HOME}/instances/default/config.json"
DATABASE_URL="$(env_get "$ROOT/.env" DATABASE_URL || env_get /etc/paperclip/.env DATABASE_URL)"

if [[ ! -d "$VENDOR_DIR" ]]; then
    echo "VENDOR_DIR not found: $VENDOR_DIR — run setup-native.sh first." >&2
    exit 1
fi

ilog="$(mktemp)"
set +e
cd "$VENDOR_DIR"
if [[ "${1:-}" == "--force" ]]; then
    env PAPERCLIP_HOME="${PAPERCLIP_SVC_HOME}" PAPERCLIP_CONFIG="${PAPERCLIP_CONFIG}" DATABASE_URL="${DATABASE_URL}" \
        pnpm paperclipai auth bootstrap-ceo --force 2>&1 | tee "$ilog"
else
    env PAPERCLIP_HOME="${PAPERCLIP_SVC_HOME}" PAPERCLIP_CONFIG="${PAPERCLIP_CONFIG}" DATABASE_URL="${DATABASE_URL}" \
        pnpm paperclipai auth bootstrap-ceo 2>&1 | tee "$ilog"
fi
set -e

port="$(env_get "$ROOT/.env" PAPERCLIP_PORT)"
port="${port:-3100}"
pub="$(env_get "$ROOT/.env" PAPERCLIP_PUBLIC_URL)"
[[ -z "$pub" ]] && pub="http://127.0.0.1:${port}"

refresh_start_here_from_log "$ROOT" "$ilog" "$pub" || true
rm -f "$ilog"

# --- Ensure a default company exists ---
echo "Ensuring a default company exists..."
if ! sudo -u postgres psql "$DATABASE_URL" -tAc "SELECT 1 FROM companies LIMIT 1" | grep -q 1; then
    env PAPERCLIP_HOME="${PAPERCLIP_SVC_HOME}" \
        PAPERCLIP_CONFIG="${PAPERCLIP_CONFIG}" \
        DATABASE_URL="${DATABASE_URL}" \
        pnpm paperclipai company create --payload-json '{"name":"My Company"}' || true
fi

print_remote_access_hint "$port" "$pub"
