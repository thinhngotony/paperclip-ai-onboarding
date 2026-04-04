#!/usr/bin/env bash
# One-shot: clone Paperclip, write .env for localhost + 9Router on host, compose up,
# wait for health, onboard (config + bootstrap CEO invite), restart server.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPOSE_FILE="${COMPOSE_FILE:-$ROOT/docker-compose.yml}"
VENDOR_DIR="${VENDOR_DIR:-$ROOT/vendor/paperclip}"
PAPERCLIP_GIT_URL="${PAPERCLIP_GIT_URL:-https://github.com/paperclipai/paperclip.git}"
PAPERCLIP_GIT_REF="${PAPERCLIP_GIT_REF:-master}"
FORCE_ONBOARD=0
UPDATE_VENDOR=0

usage() {
  echo "Automates Paperclip Docker install, localhost URLs, 9Router proxy env, and CEO bootstrap."
  echo "Usage: $0 [--force-onboard] [--update-vendor]"
  echo "  --force-onboard   Run onboard -y even if config.json already exists"
  echo "  --update-vendor   git fetch + reset to PAPERCLIP_GIT_REF and rebuild image"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-onboard) FORCE_ONBOARD=1 ;;
    --update-vendor) UPDATE_VENDOR=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd docker
docker compose version >/dev/null 2>&1 || {
  echo "Need Docker Compose v2 (docker compose)" >&2
  exit 1
}
need_cmd curl
need_cmd git
need_cmd openssl

ensure_env_file() {
  if [[ -f "$ROOT/.env" ]]; then
    return 0
  fi
  echo "Creating $ROOT/.env from localhost + 9Router defaults..."
  local auth agent
  auth="$(openssl rand -hex 32)"
  agent="$(openssl rand -hex 32)"
  cat >"$ROOT/.env" <<EOF
PAPERCLIP_PORT=3100
PAPERCLIP_PUBLIC_URL=http://127.0.0.1:3100
PAPERCLIP_ALLOWED_HOSTNAMES=127.0.0.1,localhost
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=private
BETTER_AUTH_SECRET=${auth}
PAPERCLIP_AGENT_JWT_SECRET=${agent}
NINEROUTER_PORT=20128
OPENAI_BASE_URL=http://host.docker.internal:20128/v1
ANTHROPIC_BASE_URL=http://host.docker.internal:20128/v1
OPENAI_API_KEY=9router-local
ANTHROPIC_API_KEY=9router-local
EOF
  echo "Wrote new .env (secrets generated)."
}

ensure_paperclip_src() {
  if [[ "$UPDATE_VENDOR" -eq 1 ]] || [[ ! -f "$VENDOR_DIR/server/package.json" ]]; then
    if [[ -d "$VENDOR_DIR/.git" ]]; then
      echo "Updating Paperclip source at $VENDOR_DIR (ref: $PAPERCLIP_GIT_REF)..."
      git -C "$VENDOR_DIR" fetch --depth 1 origin "$PAPERCLIP_GIT_REF" || true
      git -C "$VENDOR_DIR" reset --hard "origin/${PAPERCLIP_GIT_REF}" 2>/dev/null || \
        git -C "$VENDOR_DIR" reset --hard "FETCH_HEAD" 2>/dev/null || \
        git -C "$VENDOR_DIR" reset --hard "$PAPERCLIP_GIT_REF"
    else
      echo "Cloning Paperclip into $VENDOR_DIR ..."
      mkdir -p "$(dirname "$VENDOR_DIR")"
      rm -rf "$VENDOR_DIR"
      if ! git clone --depth 1 --branch "$PAPERCLIP_GIT_REF" "$PAPERCLIP_GIT_URL" "$VENDOR_DIR"; then
        git clone --depth 1 "$PAPERCLIP_GIT_URL" "$VENDOR_DIR"
        git -C "$VENDOR_DIR" checkout "$PAPERCLIP_GIT_REF"
      fi
    fi
  else
    echo "Using existing Paperclip source at $VENDOR_DIR"
  fi
}

read_env_kv() {
  local key="$1"
  local line
  line="$(grep -E "^${key}=" "$ROOT/.env" 2>/dev/null | head -1 || true)"
  echo "${line#*=}" | tr -d '\r'
}

ninerouter_probe() {
  local port
  port="$(read_env_kv NINEROUTER_PORT)"
  port="${port:-20128}"
  if curl -sfS "http://127.0.0.1:${port}/v1/models" >/dev/null; then
    echo "9Router reachable at http://127.0.0.1:${port}/v1 (host)."
  else
    echo "Warning: could not reach 9Router at http://127.0.0.1:${port}/v1/models" >&2
    echo "  Start 9Router on the host, or set NINEROUTER_PORT / OPENAI_BASE_URL / ANTHROPIC_BASE_URL in .env" >&2
  fi
}

wait_health() {
  local port
  port="$(read_env_kv PAPERCLIP_PORT)"
  port="${port:-3100}"
  local url="http://127.0.0.1:${port}/api/health"
  echo "Waiting for Paperclip at $url ..."
  local i
  for i in $(seq 1 90); do
    if curl -sfS "$url" >/dev/null; then
      echo "Paperclip is healthy."
      return 0
    fi
    sleep 2
  done
  echo "Timeout waiting for health." >&2
  exit 1
}

config_exists_in_container() {
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" exec -T server \
    sh -c 'test -f /paperclip/instances/default/config.json' >/dev/null 2>&1
}

run_onboard() {
  local log
  log="$(mktemp)"
  echo "Running paperclipai onboard -y (bootstrap CEO invite + config)..."
  set +e
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" exec -T server \
    sh -c 'cd /app && pnpm paperclipai onboard -y' 2>&1 | tee "$log"
  local st="${PIPESTATUS[0]}"
  set -e
  echo "Restarting server container to drop any extra Node listener onboard may have started..."
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" restart server
  wait_health
  if [[ $st -ne 0 ]]; then
    echo "onboard exited with status $st — full log: $log" >&2
    exit "$st"
  fi
  if grep -q 'Invite URL:' "$log" 2>/dev/null; then
    echo ""
    echo "---- Bootstrap invite (open in browser) ----"
    grep 'Invite URL:' "$log" | sed 's/.*Invite URL:[[:space:]]*//' | head -1
    echo "--------------------------------------------"
  fi
  rm -f "$log"
}

main() {
  ensure_env_file
  ensure_paperclip_src
  ninerouter_probe

  echo "Building and starting stack..."
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" build server
  docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/.env" up -d

  wait_health

  if config_exists_in_container && [[ "$FORCE_ONBOARD" -eq 0 ]]; then
    echo "Paperclip config already present; skipping onboard. Use --force-onboard to re-run."
  else
    run_onboard
  fi

  local port
  port="$(read_env_kv PAPERCLIP_PORT)"
  port="${port:-3100}"
  echo ""
  echo "Done. UI: http://127.0.0.1:${port}"
  echo "Use a 9Router model id (e.g. from /v1/models) in agent settings."
}

main "$@"
