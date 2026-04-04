#!/usr/bin/env bash
# shellcheck shell=bash
# Sourced by setup.sh / bootstrap-ceo.sh — not executed directly.

print_remote_access_hint() {
  local port="${1:-3100}"
  local public_url="${2:-}"
  echo ""
  if [[ -n "$public_url" ]] && [[ "$public_url" != *"127.0.0.1"* ]] && [[ "$public_url" != *"localhost"* ]]; then
    echo "---- Access from the internet (VPS) ----"
    echo "Open: ${public_url}"
    echo "Ensure TCP port ${port} is allowed in your cloud firewall / security group."
    echo "----------------------------------------"
    echo ""
  fi
  echo "---- SSH port forward (optional) ----"
  echo "http://127.0.0.1:${port} is this machine's loopback — not your laptop unless you tunnel:"
  echo ""
  echo "  ssh -N -L ${port}:127.0.0.1:${port} USER@THIS_HOST"
  echo ""
  echo "Then open http://127.0.0.1:${port} locally. Invite links work through the tunnel."
  echo "-------------------------------------"
}
