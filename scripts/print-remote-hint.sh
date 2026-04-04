#!/usr/bin/env bash
# Print SSH port-forward instructions (same text as after setup/bootstrap-ceo).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/access-hint.sh
. "$ROOT/scripts/lib/access-hint.sh"
port="$(grep -E '^PAPERCLIP_PORT=' "$ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r')"
port="${port:-3100}"
print_remote_access_hint "$port"
