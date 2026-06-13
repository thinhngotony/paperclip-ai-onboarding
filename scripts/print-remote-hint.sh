#!/usr/bin/env bash
# Print SSH port-forward instructions (same text as after setup/bootstrap-ceo).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/vps-env.sh
. "$ROOT/scripts/lib/vps-env.sh"
# shellcheck source=lib/access-hint.sh
. "$ROOT/scripts/lib/access-hint.sh"
port="$(env_get "$ROOT/.env" PAPERCLIP_PORT 2>/dev/null || true)"
port="${port:-3100}"
pub="$(env_get "$ROOT/.env" PAPERCLIP_PUBLIC_URL 2>/dev/null || true)"
print_remote_access_hint "$port" "$pub"
