#!/usr/bin/env bash
# Native VPS installer for Paperclip (no Docker).
# Fully automated, idempotent: safe to re-run.
# Installs Node.js, pnpm, PostgreSQL, builds Paperclip, sets up systemd service.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Source helper libraries
# shellcheck source=lib/access-hint.sh
. "$ROOT/scripts/lib/access-hint.sh"
# shellcheck source=lib/vps-env.sh
. "$ROOT/scripts/lib/vps-env.sh"
# shellcheck source=lib/finalize-invite.sh
. "$ROOT/scripts/lib/finalize-invite.sh"
# shellcheck source=lib/9router-env.sh
. "$ROOT/scripts/lib/9router-env.sh"

# ── Configurable paths ──────────────────────────────────────────────
# VENDOR_DIR must be accessible by the 'paperclip' systemd service user.
# /root is NOT accessible (drwx------); default to /opt.
VENDOR_DIR="${VENDOR_DIR:-/opt/paperclip-ai-onboarding/vendor/paperclip}"
PAPERCLIP_GIT_URL="${PAPERCLIP_GIT_URL:-https://github.com/paperclipai/paperclip.git}"
PAPERCLIP_GIT_REF="${PAPERCLIP_GIT_REF:-master}"

# ── Service user paths (must match systemd unit template) ──────────
PAPERCLIP_SVC_USER="${PAPERCLIP_SVC_USER:-paperclip}"
PAPERCLIP_SVC_HOME="/var/lib/paperclip"
PAPERCLIP_SVC_INSTANCE="${PAPERCLIP_SVC_INSTANCE:-default}"

FLAG_LOCAL=0
FLAG_FORCE_ONBOARD=0
FLAG_UPDATE_VENDOR=0
FLAG_REFRESH_9ROUTER_KEY=0
FLAG_DRY_RUN=0
FLAG_SKIP_DEPS=0

usage() {
    cat <<USAGE
Native VPS installer for Paperclip (fully automated, idempotent).

Usage: $0 [options]

Options:
  --local               Loopback-only (127.0.0.1), no public hostname allow-list
  --force-onboard       Re-run onboard even if config.json already exists
  --update-vendor       git fetch + reset to PAPERCLIP_GIT_REF and rebuild
  --refresh-9router-key Replace OPENAI_API_KEY when re-syncing 9Router settings
  --dry-run             Show what would be done without executing
  --skip-deps           Skip system dependency installation
  -h, --help            Show this help

Environment overrides:
  VENDOR_DIR            Where to clone/build Paperclip (default: /opt/paperclip-ai-onboarding/vendor/paperclip)
  PAPERCLIP_GIT_URL     Paperclip repo URL
  PAPERCLIP_GIT_REF     Git ref to checkout (default: master)
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)                FLAG_LOCAL=1 ;;
        --force-onboard)        FLAG_FORCE_ONBOARD=1 ;;
        --update-vendor)        FLAG_UPDATE_VENDOR=1 ;;
        --refresh-9router-key)  FLAG_REFRESH_9ROUTER_KEY=1 ;;
        --dry-run)              FLAG_DRY_RUN=1 ;;
        --skip-deps)            FLAG_SKIP_DEPS=1 ;;
        -h|--help)              usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

run() {
    if [[ "$FLAG_DRY_RUN" -eq 1 ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# ────────────────────────────────────────────────────────────────────
# Step 1 – System dependencies
# ────────────────────────────────────────────────────────────────────
install_system_deps() {
    echo "Checking system dependencies..."

    if [[ "$FLAG_SKIP_DEPS" -eq 1 ]]; then
        echo "Skipping dependency installation (--skip-deps)"
        return 0
    fi

    local missing=()
    for cmd in curl git openssl; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Installing missing system packages: ${missing[*]}"
        run apt-get update
        run apt-get install -y --no-install-recommends "${missing[@]}"
    fi

    # Node.js >= 20
    if command -v node >/dev/null 2>&1; then
        local node_ver
        node_ver=$(node -v | sed 's/v//' | cut -d. -f1)
        if [[ "$node_ver" -ge 20 ]]; then
            echo "Node.js $(node -v) found (>= 20)"
        else
            echo "Node.js $(node -v) is too old. Installing Node.js 20.x..." >&2
            run curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
            run apt-get install -y --no-install-recommends nodejs
        fi
    else
        echo "Installing Node.js 20.x..."
        run curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        run apt-get install -y --no-install-recommends nodejs
    fi

    # pnpm
    if command -v pnpm >/dev/null 2>&1; then
        echo "pnpm $(pnpm -v) found"
    else
        echo "Installing pnpm..."
        run npm install -g pnpm
    fi

    # PostgreSQL
    if command -v psql >/dev/null 2>&1; then
        echo "PostgreSQL found"
    else
        echo "Installing PostgreSQL..."
        run apt-get install -y --no-install-recommends postgresql postgresql-contrib
    fi

    echo "System dependencies ready."
}

# ────────────────────────────────────────────────────────────────────
# Step 2 – PostgreSQL
# ────────────────────────────────────────────────────────────────────
setup_postgres() {
    echo "Setting up PostgreSQL..."

    if command -v systemctl >/dev/null 2>&1; then
        run systemctl start postgresql || true
        run systemctl enable postgresql || true
    elif command -v service >/dev/null 2>&1; then
        run service postgresql start || true
    fi

    for i in $(seq 1 30); do
        if sudo -u postgres psql -c '\q' 2>/dev/null; then
            break
        fi
        sleep 1
    done

    run sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='paperclip'" 2>/dev/null | grep -q 1 || \
        run sudo -u postgres psql -c "CREATE USER paperclip WITH PASSWORD 'paperclip' CREATEDB;"

    run sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='paperclip'" 2>/dev/null | grep -q 1 || \
        run sudo -u postgres psql -c "CREATE DATABASE paperclip OWNER paperclip;"

    echo "PostgreSQL ready (paperclip@localhost/paperclip)"
}

# ────────────────────────────────────────────────────────────────────
# Step 3 – .env file
# ────────────────────────────────────────────────────────────────────
DATABASE_URL_DEFAULT="postgres://paperclip:paperclip@localhost:5432/paperclip"

ensure_env_file() {
    if [[ -f "$ROOT/.env" ]]; then
        echo "Using existing $ROOT/.env"
        # Ensure DATABASE_URL is set (migrate from old setups if needed)
        if ! grep -q '^DATABASE_URL=' "$ROOT/.env" 2>/dev/null; then
            echo "Adding DATABASE_URL to existing .env"
            echo "DATABASE_URL=${DATABASE_URL_DEFAULT}" >> "$ROOT/.env"
        fi
        return 0
    fi

    echo "Creating $ROOT/.env ..."
    local auth agent
    auth="$(openssl rand -hex 32)"
    agent="$(openssl rand -hex 32)"

    cat >"$ROOT/.env" <<EOF
PAPERCLIP_NETWORK_PROFILE=vps
PAPERCLIP_PORT=3100
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=private
BETTER_AUTH_SECRET=${auth}
PAPERCLIP_AGENT_JWT_SECRET=${agent}
DATABASE_URL=${DATABASE_URL_DEFAULT}
NINEROUTER_PORT=20128
# 9Router config will be synced below
EOF
    echo "Wrote new .env."
}

# ────────────────────────────────────────────────────────────────────
# Step 4 – Paperclip source (clone / update)
# ────────────────────────────────────────────────────────────────────
ensure_paperclip_src() {
    if [[ "$FLAG_UPDATE_VENDOR" -eq 1 ]] || [[ ! -f "$VENDOR_DIR/server/package.json" ]]; then
        if [[ -d "$VENDOR_DIR/.git" ]]; then
            echo "Updating Paperclip source at $VENDOR_DIR ..."
            run git -C "$VENDOR_DIR" fetch --depth 1 origin "$PAPERCLIP_GIT_REF" || true
            run git -C "$VENDOR_DIR" reset --hard "origin/${PAPERCLIP_GIT_REF}" 2>/dev/null || \
            run git -C "$VENDOR_DIR" reset --hard "FETCH_HEAD" 2>/dev/null || \
            run git -C "$VENDOR_DIR" reset --hard "$PAPERCLIP_GIT_REF"
        else
            echo "Cloning Paperclip into $VENDOR_DIR ..."
            run mkdir -p "$(dirname "$VENDOR_DIR")"
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

# ────────────────────────────────────────────────────────────────────
# Step 5 – Build Paperclip (correct dependency order)
# ────────────────────────────────────────────────────────────────────
build_paperclip() {
    echo "Installing Paperclip dependencies..."
    if [[ "$FLAG_DRY_RUN" -eq 0 ]]; then
        cd "$VENDOR_DIR"
        # Plugin postinstall hooks (EEXIST symlinks) are non-fatal.
        # Run install with set +e, then verify critical deps exist.
        set +e
        pnpm install --frozen-lockfile 2>&1 || true
        set -e
    else
        run pnpm install --frozen-lockfile
    fi

    # Verify critical native addon (sqlite3) exists; rebuild if needed.
    local sqlite_built
    sqlite_built=$(find "$VENDOR_DIR/node_modules/.pnpm/sqlite3@"* -name "node_sqlite3.node" 2>/dev/null | head -1)
    if [[ -z "$sqlite_built" ]]; then
        echo "Rebuilding sqlite3 native addon..."
        local sqlite_dir
        sqlite_dir=$(find "$VENDOR_DIR/node_modules/.pnpm/sqlite3@"* -name "binding.gyp" -type f 2>/dev/null | head -1 | xargs dirname)
        if [[ -n "$sqlite_dir" ]]; then
            run bash -c "cd \"$sqlite_dir\" && node-gyp rebuild" 2>/dev/null || true
        fi
    fi

    # Build order: shared (dep of plugin-sdk) → plugin-sdk → ui → server
    echo "Building @paperclipai/shared..."
    run pnpm --filter @paperclipai/shared build

    echo "Building @paperclipai/plugin-sdk..."
    run pnpm --filter @paperclipai/plugin-sdk build

    echo "Building @paperclipai/ui..."
    run pnpm --filter @paperclipai/ui build

    echo "Building @paperclipai/server..."
    run pnpm --filter @paperclipai/server build

    echo "Paperclip built successfully."
}

# ────────────────────────────────────────────────────────────────────
# Step 6 – Database migrations
# ────────────────────────────────────────────────────────────────────
run_migrations() {
    echo "Running database migrations..."
    if [[ "$FLAG_DRY_RUN" -eq 0 ]]; then
        cd "$VENDOR_DIR"
    fi
    local db_url
    db_url="$(env_get "$ROOT/.env" DATABASE_URL || echo "$DATABASE_URL_DEFAULT")"
    run env DATABASE_URL="$db_url" pnpm --filter @paperclipai/db migrate
    echo "Migrations complete."
}

# ────────────────────────────────────────────────────────────────────
# Step 7 – systemd service
# ────────────────────────────────────────────────────────────────────
install_systemd_service() {
    echo "Installing systemd service..."

    # Service user
    id -u "$PAPERCLIP_SVC_USER" >/dev/null 2>&1 || \
        run useradd -r -s /bin/false -d "$PAPERCLIP_SVC_HOME" "$PAPERCLIP_SVC_USER"

    # Data + config directories
    run mkdir -p "$PAPERCLIP_SVC_HOME"
    run chown "${PAPERCLIP_SVC_USER}:${PAPERCLIP_SVC_USER}" "$PAPERCLIP_SVC_HOME"
    run mkdir -p /etc/paperclip
    run cp "$ROOT/.env" /etc/paperclip/.env
    run chown "${PAPERCLIP_SVC_USER}:${PAPERCLIP_SVC_USER}" /etc/paperclip/.env

    # Render systemd unit template
    local unit="/etc/systemd/system/paperclip.service"
    sed -e "s|%%VENDOR_DIR%%|$VENDOR_DIR|g" \
        -e "s|%%SVC_HOME%%|$PAPERCLIP_SVC_HOME|g" \
        -e "s|%%SVC_USER%%|$PAPERCLIP_SVC_USER|g" \
        -e "s|%%SVC_INSTANCE%%|$PAPERCLIP_SVC_INSTANCE|g" \
        "$ROOT/scripts/systemd/paperclip.service.template" > "$unit"
    run chown root:root "$unit"
    run chmod 644 "$unit"

    run systemctl daemon-reload
    run systemctl enable paperclip
    echo "Systemd service installed."
}

# ────────────────────────────────────────────────────────────────────
# Step 8 – Start service + wait for health
# ────────────────────────────────────────────────────────────────────
start_service() {
    echo "Starting Paperclip service..."
    run systemctl stop paperclip 2>/dev/null || true
    run systemctl start paperclip

    local port
    port="$(env_get "$ROOT/.env" PAPERCLIP_PORT)"
    port="${port:-3100}"
    local url="http://127.0.0.1:${port}/api/health"

    echo "Waiting for Paperclip at $url ..."
    for i in $(seq 1 90); do
        if curl -sfS "$url" >/dev/null 2>&1; then
            echo "Paperclip is healthy."
            return 0
        fi
        sleep 2
    done
    echo "Timeout waiting for health — check: journalctl -u paperclip -n 50" >&2
    return 1
}

# ────────────────────────────────────────────────────────────────────
# Step 9 – Onboard + bootstrap CEO
# ────────────────────────────────────────────────────────────────────
run_onboard_and_bootstrap() {
    local config_path="${PAPERCLIP_SVC_HOME}/instances/${PAPERCLIP_SVC_INSTANCE}/config.json"
    local db_url
    db_url="$(env_get /etc/paperclip/.env DATABASE_URL 2>/dev/null || env_get "$ROOT/.env" DATABASE_URL)"

    if [[ -f "$config_path" ]] && [[ "$FLAG_FORCE_ONBOARD" -eq 0 ]]; then
        echo "Paperclip config already present; skipping onboard. Use --force-onboard to re-run."
        # Still try bootstrap-ceo in case it's needed
    else
        echo "Running paperclipai onboard -y..."
        if [[ "$FLAG_DRY_RUN" -eq 0 ]]; then
            cd "$VENDOR_DIR"
        fi
        # Onboard internally runs paperclipai run, which starts a server and blocks.
        # Use timeout to kill it after config is written.
        run env PAPERCLIP_HOME="${PAPERCLIP_SVC_HOME}" \
            PAPERCLIP_CONFIG="${config_path}" \
            DATABASE_URL="${db_url}" \
            timeout --signal=SIGKILL 90s pnpm paperclipai onboard -y 2>&1 || true
        # Kill any stray paperclipai processes the onboard may have spawned
        run pkill -f "paperclipai run" 2>/dev/null || true
        run pkill -f "paperclipai onboard" 2>/dev/null || true

        # Onboard may write config under PAPERCLIP_HOME/.paperclip
        # if PAPERCLIP_CONFIG wasn't respected. Copy it if needed.
        local cli_config="${PAPERCLIP_SVC_HOME}/.paperclip/instances/${PAPERCLIP_SVC_INSTANCE}/config.json"
        if [[ -f "$cli_config" ]] && [[ ! -f "$config_path" ]]; then
            run mkdir -p "$(dirname "$config_path")"
            run cp "$cli_config" "$config_path"
            local cli_dir; cli_dir="$(dirname "$cli_config")"
            local svc_dir; svc_dir="$(dirname "$config_path")"
            for sub in secrets data; do
                if [[ -d "${cli_dir}/${sub}" ]] && [[ ! -d "${svc_dir}/${sub}" ]]; then
                    run cp -a "${cli_dir}/${sub}" "${svc_dir}/"
                fi
            done
            echo "Copied onboard config to $config_path"
        fi

        # Force deploymentMode to authenticated (onboard defaults to local_trusted)
        if [[ -f "$config_path" ]]; then
            run python3 -c "
import json; import sys
with open('$config_path') as f: c = json.load(f)
c['server']['deploymentMode'] = 'authenticated'
c['server']['bind'] = 'lan'
# Ensure database mode matches
if not c.get('database') or c['database'].get('mode') == 'embedded-postgres':
    c['database'] = {'mode': 'postgres', 'connectionString': '$db_url'}
with open('$config_path', 'w') as f: json.dump(c, f, indent=2)
" 2>/dev/null || echo "Warning: could not patch config for authenticated mode" >&2
            run chown "${PAPERCLIP_SVC_USER}:${PAPERCLIP_SVC_USER}" "$config_path"
            run chown -R "${PAPERCLIP_SVC_USER}:${PAPERCLIP_SVC_USER}" "$(dirname "$config_path")" 2>/dev/null || true
        fi

        # Restart service to pick up new config
        run systemctl restart paperclip
        start_service
    fi

    # Now bootstrap the CEO admin invite
    echo "Bootstrapping CEO admin invite..."
    if [[ "$FLAG_DRY_RUN" -eq 0 ]]; then
        cd "$VENDOR_DIR"
    fi
    local ilog
    ilog="$(mktemp)"

    set +e
    run env PAPERCLIP_HOME="${PAPERCLIP_SVC_HOME}" \
        PAPERCLIP_CONFIG="${config_path}" \
        PAPERCLIP_INSTANCE_ID="${PAPERCLIP_SVC_INSTANCE}" \
        DATABASE_URL="${db_url}" \
        pnpm paperclipai auth bootstrap-ceo 2>&1 | tee "$ilog"
    local rc="${PIPESTATUS[0]}"
    set -e

    if [[ $rc -ne 0 ]]; then
        echo "bootstrap-ceo failed (exit $rc)." >&2
        cat "$ilog" >&2
        rm -f "$ilog"
        return 1
    fi

    local out_dir
    out_dir="$(dirname "$VENDOR_DIR")"
    refresh_start_here_from_log "$out_dir" "$ilog" "$pub" || true
    rm -f "$ilog"

    # --- Auto-create a default company if none exist ---
    echo "Ensuring a default company exists..."
    if ! sudo -u postgres psql "$db_url" -tAc "SELECT 1 FROM companies LIMIT 1" | grep -q 1; then
        run env PAPERCLIP_HOME="${PAPERCLIP_SVC_HOME}" \
            PAPERCLIP_CONFIG="${config_path}" \
            DATABASE_URL="${db_url}" \
            pnpm paperclipai company create --payload-json '{"name":"My Company"}'
    else
        echo "Company already present – skipping creation."
    fi
}

# ────────────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────────────
main() {
    echo "=============================================="
    echo "Paperclip Native VPS Installer"
    echo "=============================================="

    # 1 Dependencies
    install_system_deps

    # 2 PostgreSQL
    setup_postgres

    # 3 .env
    ensure_env_file

    # --local profile (must run before sync_vps_env_file)
    if [[ "$FLAG_LOCAL" -eq 1 ]]; then
        force_local_network_profile "$ROOT"
    fi

    # 4 VPS env (public URL + allowed hostnames)
    sync_vps_env_file "$ROOT"

    # 5 9Router
    if sync_9router_llm_env "$ROOT" "$FLAG_REFRESH_9ROUTER_KEY"; then
        run sed -i 's|host\.docker\.internal|127.0.0.1|g' "$ROOT/.env"
    else
        echo "Continuing without 9Router auto-sync." >&2
    fi

    # 6 Source
    ensure_paperclip_src

    # 7 Build
    build_paperclip

    # 8 Migrations
    run_migrations

    # 10 Systemd service (also copies env to /etc/paperclip)
    install_systemd_service

    # 11 Start service
    start_service

    # Final: compute pub URL for onboarding
    local port pub
    port="$(env_get "$ROOT/.env" PAPERCLIP_PORT)"
    port="${port:-3100}"
    pub="$(env_get "$ROOT/.env" PAPERCLIP_PUBLIC_URL)"
    [[ -z "$pub" ]] && pub="http://127.0.0.1:${port}"

    # 12 Onboard + bootstrap CEO
    run_onboard_and_bootstrap

    echo ""
    echo "Setup finished."
    echo " Local UI: http://127.0.0.1:${port}"
    print_remote_access_hint "$port" "$pub"

    echo ""
    echo "=============================================="
    echo "Paperclip native install complete!"
    echo "=============================================="
}

main "$@"
