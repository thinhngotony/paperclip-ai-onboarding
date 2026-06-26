#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

. "$ROOT/scripts/lib/vps-env.sh" 2>/dev/null || true
. "$ROOT/scripts/lib/finalize-invite.sh" 2>/dev/null || true
. "$ROOT/scripts/lib/access-hint.sh" 2>/dev/null || true

VENDOR_DIR="${VENDOR_DIR:-/opt/paperclip-ai-onboarding/vendor/paperclip}"
PAPERCLIP_SVC_HOME="/var/lib/paperclip"
PAPERCLIP_CONFIG="${PAPERCLIP_SVC_HOME}/instances/default/config.json"

FLAG_CLEAN_SLATE=0
FLAG_DEEP_CLEAN=0
FLAG_SKIP_DEPS=0

usage() {
    cat <<USAGE
Unified Paperclip native installer + onboarding.

Usage: $0 [options]

Options:
  --clean-slate    Wipe admin/company data (keeps user accounts)
  --deep-clean     Wipe EVERYTHING including all users (full factory reset)
  --skip-deps      Skip system dependency installation
  -h, --help       Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean-slate)  FLAG_CLEAN_SLATE=1 ;;
        --deep-clean)   FLAG_DEEP_CLEAN=1 ;;
        --skip-deps)    FLAG_SKIP_DEPS=1 ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

get_db_url() {
    if [[ -f /etc/paperclip/.env ]]; then
        grep '^DATABASE_URL=' /etc/paperclip/.env 2>/dev/null | cut -d= -f2- || echo ""
    else
        echo ""
    fi
}

if [[ "$FLAG_DEEP_CLEAN" -eq 1 ]]; then
    echo "=== Deep clean: wiping ALL data ==="
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop paperclip 2>/dev/null || true
    fi
    db_url="$(get_db_url)"
    if [[ -n "$db_url" ]]; then
        sudo -u postgres psql "$db_url" -c "
            TRUNCATE TABLE
                principal_permission_grants,
                company_skills, company_skill_versions, company_skill_comments, company_skill_stars,
                company_logos, company_secret_bindings, company_secret_provider_configs,
                company_secret_versions, company_secrets,
                company_memberships,
                companies,
                invites,
                account,
                instance_user_roles,
                session,
                verification
            CASCADE;
        " 2>/dev/null || true
        sudo -u postgres psql "$db_url" -c "DELETE FROM \"user\" WHERE id != 'local-board';" 2>/dev/null || true
    fi
    INSTANCE_DIR="${PAPERCLIP_SVC_HOME}/instances/default"
    for subdir in data/storage logs telemetry; do
        rm -rf "${INSTANCE_DIR}/${subdir}" 2>/dev/null || true
    done
    mkdir -p "${INSTANCE_DIR}/data/storage" "${INSTANCE_DIR}/logs" "${INSTANCE_DIR}/telemetry" 2>/dev/null || true
    echo "Deep clean complete."
fi

if [[ "$FLAG_CLEAN_SLATE" -eq 1 ]] && [[ "$FLAG_DEEP_CLEAN" -eq 0 ]]; then
    echo "=== Clean slate: removing admin/company data ==="
    if command -v systemctl >/dev/null 2>&1; then
        systemctl stop paperclip 2>/dev/null || true
    fi
    db_url="$(get_db_url)"
    if [[ -n "$db_url" ]]; then
        sudo -u postgres psql "$db_url" -c "
            DELETE FROM company_memberships;
            DELETE FROM companies;
            DELETE FROM invites WHERE invite_type='bootstrap_ceo';
            DELETE FROM instance_user_roles WHERE role='instance_admin';
        " 2>/dev/null || true
    fi
    echo "Clean slate ready."
fi

echo "=== Running base installer ==="
SETUP_ARGS="--force-onboard"
if [[ "$FLAG_SKIP_DEPS" -eq 1 ]]; then
    SETUP_ARGS="$SETUP_ARGS --skip-deps"
fi
./scripts/setup-native.sh $SETUP_ARGS

echo ""
echo "=== Awaiting admin claim ==="
echo "Open the invite URL shown above in your browser and sign in."

db_url="$(get_db_url)"
api_url="http://127.0.0.1:3100"
while true; do
    health="$(curl -sfS --max-time 5 "$api_url/api/health" 2>/dev/null || echo "")"
    if echo "$health" | grep -q '"bootstrapStatus":"ready"'; then
        echo "Admin claimed - proceeding to auto-create company..."
        break
    fi
    echo -n "."
    sleep 3
done

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
