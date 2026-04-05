#!/usr/bin/env bash
# Point Paperclip's OPENAI_* and ANTHROPIC_* (Claude Code) at 9Router on the native host.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Source helper libraries
# shellcheck source=lib/vps-env.sh
. "$ROOT/scripts/lib/vps-env.sh"
# shellcheck source=lib/9router-env.sh
. "$ROOT/scripts/lib/9router-env.sh"

REFRESH_KEY=0
RECREATE=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --refresh-key) REFRESH_KEY=1 ;;
        --no-recreate) RECREATE=0 ;;
        -h|--help)
            echo "Usage: $0 [--refresh-key] [--no-recreate]"
            echo " --refresh-key Replace OPENAI_API_KEY even if already set in .env"
            echo " --no-recreate Only update .env; do not restart Paperclip"
            exit 0
        ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

[[ -f "$ROOT/.env" ]] || { echo "Missing .env — run ./scripts/setup-native.sh first." >&2; exit 1; }

sync_9router_llm_env "$ROOT" "$REFRESH_KEY" || {
    echo "9Router sync skipped or failed; .env unchanged for LLM URLs." >&2
    exit 1
}

# Fix Docker-specific hostnames for native mode
sed -i 's|host\.docker\.internal|127.0.0.1|g' "$ROOT/.env"

# Copy to /etc/paperclip
cp "$ROOT/.env" /etc/paperclip/.env

if [[ "$RECREATE" -eq 1 ]]; then
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

    echo "Restarted paperclip service with updated 9Router settings."
else
    echo "Wrote .env; restart the server when ready: systemctl restart paperclip"
fi