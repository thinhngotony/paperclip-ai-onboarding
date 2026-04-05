#!/usr/bin/env bash
# Native VPS installer for Paperclip (no Docker).
# Installs Node.js, pnpm, PostgreSQL, builds Paperclip, sets up systemd service.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Source helper libraries (reused from Docker setup)
# shellcheck source=lib/access-hint.sh
. "$ROOT/scripts/lib/access-hint.sh"
# shellcheck source=lib/vps-env.sh
. "$ROOT/scripts/lib/vps-env.sh"
# shellcheck source=lib/finalize-invite.sh
. "$ROOT/scripts/lib/finalize-invite.sh"
# shellcheck source=lib/9router-env.sh
. "$ROOT/scripts/lib/9router-env.sh"

VENDOR_DIR="${VENDOR_DIR:-$ROOT/vendor/paperclip}"
PAPERCLIP_GIT_URL="${PAPERCLIP_GIT_URL:-https://github.com/paperclipai/paperclip.git}"
PAPERCLIP_GIT_REF="${PAPERCLIP_GIT_REF:-master}"

FORCE_ONBOARD=0
UPDATE_VENDOR=0
LOCAL_ONLY=0
REFRESH_9ROUTER_KEY=0
DRY_RUN=0
SKIP_DEPS=0

usage() {
    echo "Native VPS installer for Paperclip (no Docker)."
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --local             Loopback-only (127.0.0.1), no public hostname allow-list"
    echo "  --force-onboard    Run onboard even if config.json already exists"
    echo "  --update-vendor    git fetch + reset to PAPERCLIP_GIT_REF and rebuild"
    echo "  --refresh-9router-key  Replace OPENAI_API_KEY when re-syncing 9Router settings"
    echo "  --dry-run          Show what would be done without executing"
    echo "  --skip-deps        Skip system dependency installation (assume Node/pnpm/Postgres present)"
    echo "  -h, --help         Show this help"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local) LOCAL_ONLY=1 ;;
        --force-onboard) FORCE_ONBOARD=1 ;;
        --update-vendor) UPDATE_VENDOR=1 ;;
        --refresh-9router-key) REFRESH_9ROUTER_KEY=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --skip-deps) SKIP_DEPS=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# Helper to run commands in dry-run mode
run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

# =============================================================================
# Step 1: Check/install system dependencies
# =============================================================================

install_system_deps() {
    echo "Checking system dependencies..."

    if [[ "$SKIP_DEPS" -eq 1 ]]; then
        echo "Skipping dependency installation (--skip-deps)"
        return 0
    fi

    missing=()

    # Check essential commands
    for cmd in curl git openssl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Installing missing system packages: ${missing[*]}"
        run apt-get update
        run apt-get install -y --no-install-recommends "${missing[@]}"
    fi

    # Check Node.js >= 20
    if command -v node >/dev/null 2>&1; then
        node_ver=$(node -v | sed 's/v//' | cut -d. -f1)
        if [[ "$node_ver" -ge 20 ]]; then
            echo "Node.js $(node -v) found (>= 20)"
        else
            echo "Node.js $(node -v) is too old, need >= 20" >&2
            echo "Installing Node.js 20.x..." >&2
            run curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
            run apt-get install -y --no-install-recommends nodejs
        fi
    else
        echo "Node.js not found, installing Node.js 20.x..."
        run curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        run apt-get install -y --no-install-recommends nodejs
    fi

    # Check/install pnpm
    if command -v pnpm >/dev/null 2>&1; then
        echo "pnpm $(pnpm -v) found"
    else
        echo "Installing pnpm..."
        run npm install -g pnpm
    fi

    # Check/install PostgreSQL
    if command -v psql >/dev/null 2>&1; then
        echo "PostgreSQL found"
    else
        echo "Installing PostgreSQL..."
        run apt-get install -y --no-install-recommends postgresql postgresql-contrib
    fi

    echo "System dependencies ready."
}

# =============================================================================
# Step 2: Ensure PostgreSQL is running and configured
# =============================================================================

setup_postgres() {
    echo "Setting up PostgreSQL..."

    # Start PostgreSQL if not running
    if command -v systemctl >/dev/null 2>&1; then
        run systemctl start postgresql || true
        run systemctl enable postgresql || true
    elif command -v service >/dev/null 2>&1; then
        run service postgresql start || true
    fi

    # Wait for PostgreSQL to be ready
    for i in $(seq 1 30); do
        if sudo -u postgres psql -c '\q' 2>/dev/null; then
            break
        fi
        sleep 1
    done

    # Create user and database if they don't exist
    run sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='paperclip'" | grep -q 1 || \
        run sudo -u postgres psql -c "CREATE USER paperclip WITH PASSWORD 'paperclip' CREATEDB;"

    run sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='paperclip'" | grep -q 1 || \
        run sudo -u postgres psql -c "CREATE DATABASE paperclip OWNER paperclip;"

    echo "PostgreSQL ready (paperclip:paperclip@localhost:5434/paperclip)"
}

# =============================================================================
# Step 3: Ensure .env file exists
# =============================================================================

ensure_env_file() {
    if [[ -f "$ROOT/.env" ]]; then
        echo "Using existing $ROOT/.env"
        return 0
    fi

    echo "Creating $ROOT/.env (secrets generated)..."
    auth="$(openssl rand -hex 32)"
    agent="$(openssl rand -hex 32)"

    cat >"$ROOT/.env" <<EOF
PAPERCLIP_NETWORK_PROFILE=vps
PAPERCLIP_PORT=3100
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=private
BETTER_AUTH_SECRET=${auth}
PAPERCLIP_AGENT_JWT_SECRET=${agent}
DATABASE_URL=postgres://paperclip:paperclip@localhost:5434/paperclip
NINEROUTER_PORT=20128
# 9Router config will be synced below
EOF

    echo "Wrote new .env (secrets generated)."
}

# =============================================================================
# Step 4: Clone/update Paperclip source
# =============================================================================

ensure_paperclip_src() {
    if [[ "$UPDATE_VENDOR" -eq 1 ]] || [[ ! -f "$VENDOR_DIR/server/package.json" ]]; then
        if [[ -d "$VENDOR_DIR/.git" ]]; then
            echo "Updating Paperclip source at $VENDOR_DIR (ref: $PAPERCLIP_GIT_REF)..."
            run git -C "$VENDOR_DIR" fetch --depth 1 origin "$PAPERCLIP_GIT_REF" || true
            run git -C "$VENDOR_DIR" reset --hard "origin/${PAPERCLIP_GIT_REF}" 2>/dev/null || \
            run git -C "$VENDOR_DIR" reset --hard "FETCH_HEAD" 2>/dev/null || \
            run git -C "$VENDOR_DIR" reset --hard "$PAPERCLIP_GIT_REF"
        else
            echo "Cloning Paperclip into $VENDOR_DIR ..."
            mkdir -p "$(dirname "$VENDOR_DIR")"
            run rm -rf "$VENDOR_DIR"
            if ! run git clone --depth 1 --branch "$PAPERCLIP_GIT_REF" "$PAPERCLIP_GIT_URL" "$VENDOR_DIR"; then
                run git clone --depth 1 "$PAPERCLIP_GIT_URL" "$VENDOR_DIR"
                run git -C "$VENDOR_DIR" checkout "$PAPERCLIP_GIT_REF"
            fi
        fi
    else
        echo "Using existing Paperclip source at $VENDOR_DIR"
    fi
}

# =============================================================================
# Step 5: Build Paperclip
# =============================================================================

build_paperclip() {
    echo "Installing Paperclip dependencies..."
    run cd "$VENDOR_DIR"
    run pnpm install --frozen-lockfile

    echo "Building Paperclip (ui, plugin-sdk, server)..."
    run pnpm --filter @paperclipai/ui build
    run pnpm --filter @paperclipai/plugin-sdk build
    run pnpm --filter @paperclipai/server build

    echo "Paperclip built successfully."
}

# =============================================================================
# Step 6: Run database migrations
# =============================================================================

run_migrations() {
    echo "Running database migrations..."
    run cd "$VENDOR_DIR"
    run pnpm --filter @paperclipai/db migrate
    echo "Migrations complete."
}

# =============================================================================
# Step 7: Create systemd service
# =============================================================================

install_systemd_service() {
    echo "Installing systemd service..."

    # Create service user if not exists
    id -u paperclip >/dev/null 2>&1 || run useradd -r -s /bin/false -d /var/lib/paperclip paperclip

    # Create data directory
    run mkdir -p /var/lib/paperclip
    run chown paperclip:paperclip /var/lib/paperclip

    # Create config directory
    run mkdir -p /etc/paperclip
    run cp "$ROOT/.env" /etc/paperclip/.env
    run chown paperclip:paperclip /etc/paperclip/.env

    # Create systemd unit from template
    unit_file="/etc/systemd/system/paperclip.service"
    sed -e "s|%%ROOT%%|$ROOT|g" \
        -e "s|%%VENDOR_DIR%%|$VENDOR_DIR|g" \
        "$ROOT/scripts/systemd/paperclip.service.template" > "$unit_file"
    run chown root:root "$unit_file"
    run chmod 644 "$unit_file"

    run systemctl daemon-reload
    run systemctl enable paperclip

    echo "Systemd service installed."
}

# =============================================================================
# Step 8: Start service and wait for health
# =============================================================================

start_service() {
    echo "Starting Paperclip service..."
    run systemctl start paperclip

    # Wait for health
    port="$(env_get "$ROOT/.env" PAPERCLIP_PORT)"
    port="${port:-3100}"
    url="http://127.0.0.1:${port}/api/health"

    echo "Waiting for Paperclip at $url ..."
    for i in $(seq 1 90); do
        if curl -sfS "$url" >/dev/null 2>&1; then
            echo "Paperclip is healthy."
            return 0
        fi
        sleep 2
    done

    echo "Timeout waiting for health. Check: journalctl -u paperclip -n 50" >&2
    return 1
}

# =============================================================================
# Step 9: Run onboard/bootstrap-ceo
# =============================================================================

run_onboard() {
    port="$(env_get "$ROOT/.env" PAPERCLIP_PORT)"
    port="${port:-3100}"

    # Check if config already exists
    if [[ -f /var/lib/paperclip/instances/default/config.json ]] && [[ "$FORCE_ONBOARD" -eq 0 ]]; then
        echo "Paperclip config already present; skipping onboard. Use --force-onboard to re-run."
        return 0
    fi

    echo "Running paperclipai onboard -y..."
    run cd "$VENDOR_DIR"
    log="$(mktemp)"
    set +e
    run pnpm paperclipai onboard -y 2>&1 | tee "$log"
    st="${PIPESTATUS[0]}"
    set -e

    # Restart service after onboard
    run systemctl restart paperclip
    start_service

    if [[ $st -ne 0 ]]; then
        echo "onboard exited with status $st — full log: $log" >&2
        exit "$st"
    fi
    rm -f "$log"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "=============================================="
    echo "Paperclip Native VPS Installer"
    echo "=============================================="

    # Step 1: Dependencies
    install_system_deps

    # Step 2: PostgreSQL
    setup_postgres

    # Step 3: .env file
    ensure_env_file

    # Apply local-only profile if requested
    if [[ "$LOCAL_ONLY" -eq 1 ]]; then
        force_local_network_profile "$ROOT"
    fi

    # Step 4: Sync VPS env (public URL + allowed hostnames)
    sync_vps_env_file "$ROOT"

    # Step 5: Sync 9Router env
    if sync_9router_llm_env "$ROOT" "$REFRESH_9ROUTER_KEY"; then
        # Fix Docker-specific hostnames for native mode
        run sed -i 's|host\.docker\.internal|127.0.0.1|g' "$ROOT/.env"
    else
        echo "Continuing without 9Router auto-sync (set NINEROUTER_PORT or start 9Router, then run ./scripts/sync-9router-env-native.sh)." >&2
    fi

    # Copy updated env to /etc/paperclip
    run cp "$ROOT/.env" /etc/paperclip/.env 2>/dev/null || true

    # Step 6: Paperclip source
    ensure_paperclip_src

    # Step 7: Build
    build_paperclip

    # Step 8: Migrations
    run_migrations

    # Step 9: Systemd service
    install_systemd_service

    # Step 10: Start service
    start_service

    # Step 11: Onboard
    run_onboard

    # Final summary
    port="$(env_get "$ROOT/.env" PAPERCLIP_PORT)"
    port="${port:-3100}"
    pub="$(env_get "$ROOT/.env" PAPERCLIP_PUBLIC_URL)"
    [[ -z "$pub" ]] && pub="http://127.0.0.1:${port}"

    echo ""
    echo "Setup finished. Resolving admin invite + writing START_HERE.txt ..."
    emit_post_setup_summary "$ROOT" "" "$ROOT/.env" "$port" "$pub" || true

    echo "Use a 9Router model id (e.g. from /v1/models) in agent settings."
    echo " Local UI: http://127.0.0.1:${port}"
    print_remote_access_hint "$port" "$pub"

    echo ""
    echo "=============================================="
    echo "Paperclip native install complete!"
    echo "=============================================="
}

main "$@"