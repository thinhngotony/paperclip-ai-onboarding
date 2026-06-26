#!/usr/bin/env bash
set -euo pipefail

DB_URL="postgres://paperclip:paperclip@localhost:5434/paperclip"
VENDOR_DIR="/opt/paperclip-ai-onboarding/vendor/paperclip"
export PAPERCLIP_HOME="/var/lib/paperclip"
export PAPERCLIP_CONFIG="/var/lib/paperclip/instances/default/config.json"

echo "Watching for first user sign-up..."

while true; do
  COUNT=$(sudo -u postgres psql -At -d paperclip -c "SELECT count(*) FROM \"user\" WHERE id != 'local-board';" 2>/dev/null || echo "0")
  COUNT=$(echo "$COUNT" | tail -1 | tr -d ' ')

  if [[ "$COUNT" =~ ^[0-9]+\$ ]] && [[ "$COUNT" -gt 0 ]]; then
    USER_ID=$(sudo -u postgres psql -At -d paperclip -c "SELECT id FROM \"user\" WHERE id != 'local-board' ORDER BY created_at ASC LIMIT 1;" 2>/dev/null | grep -E '^[A-Za-z0-9_-]{20,}$' | tail -1)

    if [[ -n "$USER_ID" ]]; then
      HAS_ADMIN=$(sudo -u postgres psql -At -d paperclip -c "SELECT count(*) FROM instance_user_roles WHERE user_id='$USER_ID' AND role='instance_admin';" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)

      if [[ "$HAS_ADMIN" != "1" ]]; then
        echo "First user detected: $USER_ID"
        echo "Granting instance_admin..."
        sudo -u postgres psql -d paperclip -c "INSERT INTO instance_user_roles (user_id, role) VALUES ('$USER_ID', 'instance_admin');"

        COMPANY_COUNT=$(sudo -u postgres psql -At -d paperclip -c "SELECT count(*) FROM companies;" 2>/dev/null | grep -E '^[0-9]+$' | tail -1)

        if [[ "$COMPANY_COUNT" == "0" ]]; then
          echo "Creating default company..."
          cd "$VENDOR_DIR"
          env DATABASE_URL="$DB_URL" pnpm paperclipai company create --payload-json '{"name": "My Company"}' 2>/dev/null || true

          COMPANY_ID=$(sudo -u postgres psql -At -d paperclip -c "SELECT id FROM companies LIMIT 1;" 2>/dev/null | grep -E '^[0-9a-f-]{36}$' | tail -1)
          if [[ -n "$COMPANY_ID" ]]; then
            sudo -u postgres psql -d paperclip -c "INSERT INTO company_memberships (company_id, principal_type, principal_id, membership_role) VALUES ('$COMPANY_ID', 'user', '$USER_ID', 'admin');"
          fi
        fi

        echo "Onboarding complete for user $USER_ID"
        exit 0
      fi
    fi
  fi

  sleep 5
done
