#!/usr/bin/env bash
# Automated uninstall for Paperclip native deployment.
# Removes the systemd service, /opt install, and optionally PostgreSQL data.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source helpers for env_get
# shellcheck source=lib/vps-env.sh
. "$ROOT/scripts/lib/vps-env.sh" 2>/dev/null || true

DRY_RUN=0
PURGE_DB=0
PURGE_ALL=0
PURGE_COMPANY=0
FORCE=0

usage() {
    cat <<USAGE
Uninstall Paperclip native deployment.

Usage: $0 [options]

Options:
  --dry-run         Show what would be removed without doing it
  --purge-db        Also drop the PostgreSQL paperclip database and user
  --purge-company   Also delete all company data (companies, memberships, etc.)
  --purge-all       Also remove Node.js, pnpm, PostgreSQL packages
  --force           Skip confirmation prompts
  -h, --help        Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)      DRY_RUN=1 ;;
        --purge-db)     PURGE_DB=1 ;;
        --purge-all)    PURGE_ALL=1 ;;
        --purge-company) PURGE_COMPANY=1 ;;
        --force)        FORCE=1 ;;
        -h|--help)     usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

if [[ "$FORCE" -eq 0 ]]; then
    echo "This will remove Paperclip and all its data."
    if [[ "$PURGE_DB" -eq 1 ]]; then
        echo "  --purge-db: will drop PostgreSQL database 'paperclip' and user 'paperclip'"
    fi
    if [[ "$PURGE_ALL" -eq 1 ]]; then
        echo "  --purge-all: will also uninstall Node.js, pnpm, PostgreSQL packages"
    fi
    echo ""
    read -rp "Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

echo "=== Stopping Paperclip service ==="
run systemctl stop paperclip 2>/dev/null || true
run systemctl disable paperclip 2>/dev/null || true
run rm -f /etc/systemd/system/paperclip.service
run rm -f /etc/systemd/system/multi-user.target.wants/paperclip.service
run systemctl daemon-reload

echo "=== Removing Paperclip user ==="
run userdel paperclip 2>/dev/null || true
run groupdel paperclip 2>/dev/null || true

echo "=== Removing Paperclip data directories ==="
run rm -rf /var/lib/paperclip
run rm -rf /etc/paperclip

echo "=== Removing Paperclip install directory ==="
VENDOR_DIR="${VENDOR_DIR:-/opt/paperclip-ai-onboarding}"
run rm -rf "$VENDOR_DIR"

if [[ "$PURGE_COMPANY" -eq 1 ]]; then
    echo "=== Deleting all company data ==="
    # Get DB URL from the config file before removing /etc/paperclip/.env
    local db_url_purge
    db_url_purge="$(env_get /etc/paperclip/.env DATABASE_URL 2>/dev/null || echo 'postgres://paperclip:paperclip@localhost:5432/paperclip')"
    run sudo -u postgres psql "$db_url_purge" -c "
        DELETE FROM company_memberships;
        DELETE FROM companies;
    " 2>/dev/null || true
fi

if [[ "$PURGE_DB" -eq 1 ]]; then
    echo "=== Dropping PostgreSQL database and user ==="
    run sudo -u postgres psql -c "DROP DATABASE IF EXISTS paperclip;" 2>/dev/null || true
    run sudo -u postgres psql -c "DROP USER IF EXISTS paperclip;" 2>/dev/null || true
fi

if [[ "$PURGE_ALL" -eq 1 ]]; then
    echo "=== Removing system packages ==="
    run apt-get remove -y postgresql postgresql-contrib nodejs 2>/dev/null || true
    run apt-get autoremove -y 2>/dev/null || true
fi

echo ""
echo "Uninstall complete."
