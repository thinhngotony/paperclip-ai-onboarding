#!/usr/bin/env bash
# Unified Paperclip native installer + onboarding (single command)
# Handles clean re-installs: wipes existing admin/company on fresh data if requested.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Source helper libraries
. "$ROOT/scripts/lib/vps-env.sh" 2>/dev/null || true
. "$ROOT/scripts/lib/finalize-invite.sh" 2>/dev/null || true
. "$ROOT/scripts/lib/access-hint.sh" 2>/dev/null || true

VENDOR_DIR="${VENDOR_DIR:-/opt/paperclip-ai-onboarding/vendor/paperclip}"
PAPERCLIP_SVC_HOME="/var/lib/paperclip"
PAPERCLIP_CONFIG="${PAPERCLIP_SVC_HOME}/instances/default/config.json"

FLAG_CLEAN_SLATE=0
FLAG_SKIP_DEPS=0

usage() {
    cat <<USAGE
Unified Paperclip native installer + onboarding.

This single command:
  1. Installs system dependencies (Node, pnpm, PostgreSQL)
  2. Clones/builds Paperclip
  3. Wipes previous admin/company (if --clean-slate)
  4. Runs migrations and starts the service
  5. Creates bootstrap-CEO invite for first admin
  6. Waits for admin to claim in browser
  7. Auto-creates default company "My Company"

Usage: $0 [options]

Options:
  --clean-slate    Wipe existing admin/company before installing (fresh start)
  --skip-deps      Skip system dependency installation
  -h, --help      Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean-slate)  FLAG_CLEAN_SLATE=1 ;;
        --skip-deps)    FLAG_SKIP_DEPS=1 ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# Helper: extract DB URL from config or .env
get_db_url() {
    if [[ -f /etc/paperclip/.env ]]; then
        grep '^DATABASE_URL=' /etc/paperclip/.env 2>/dev/null | cut -d= -f2- || echo ""
    else
        echo ""
    fi
}

# ── Step 0: Clean slate if requested ──────────────────────────────
if [[ "$FLAG_CLEAN_SLATE" -eq 1 ]]; then
    echo "=== Clean slate: removing existing admin/company data ==="
    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl stop paperclip 2>/dev/null || true
    fi
    db_url="$(get_db_url)"
    if [[ -n "$db_url" ]]; then
        sudo -u postgres psql "$db_url" -c "
            DELETE FROM company_memberships;
            DELETE FROM companies;
            DELETE FROM invites WHERE inviteType='bootstrap_ceo';
            DELETE FROM instance_user_roles WHERE role='instance_admin';
        " 2>/dev/null || true
    fi
    echo "Clean slate ready."
fi

# ── Step 1: Run the base installer ───────────────────────────────
echo "=== Running base installer ==="
./scripts/setup-native.sh --force-onboard --skip-deps="$FLAG_SKIP_DEPS" --local

# ── Step 2: Wait for admin to claim the invite ───────────────────
echo ""
echo "=== Awaiting admin claim ==="
echo "Open the invite URL shown above in your browser and sign in."
echo "The script will auto-create a default company once you're signed in."
echo ""

# Poll until bootstrapStatus becomes "ready" (admin claimed)
db_url="$(get_db_url)"
api_url="http://127.0.0.1:3100"
while true; do
    health="$(curl -sfS --max-time 5 "$api_url/api/health" 2>/dev/null || echo "")"
    if echo "$health" | grep -q '"bootstrapStatus":"ready"'; then
        echo "Admin claimed – proceeding to auto-create company..."
        break
    fi
    echo -n "."
    sleep 3
done

# ── Step 3: Auto-create default company ───────────────────────────
echo ""
echo "=== Ensuring default company exists ==="
if ! sudo -u postgres psql "$db_url" -tAc "SELECT 1 FROM companies LIMIT 1" | grep -q 1; then
    cd "$VENDOR_DIR"
    env PAPERCLIP_HOME="${PAPERCLIP_SVC_HOME}" \
        PAPERCLIP_CONFIG="${PAPERCLIP_CONFIG}" \
        DATABASE_URL="${db_url}" \
        pnpm paperclipai company create --payload-json '{"name":"My Company"}'
    echo "Default company 'My Company' created."
else
    echo "Company already present."
fi

echo ""
echo "=== Onboarding complete ==="
echo "Open http://42.96.13.174:3100 in your browser to start using Paperclip."