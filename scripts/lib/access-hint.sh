#!/usr/bin/env bash
# shellcheck shell=bash
# Sourced by setup.sh / bootstrap-ceo.sh — not executed directly.

print_remote_access_hint() {
  local port="${1:-3100}"
  echo ""
  echo "---- Remote access (browser on your laptop, Paperclip on this server) ----"
  echo "URLs use http://127.0.0.1:${port} — that is this machine's loopback, not your laptop."
  echo "Forward the port over SSH, then use the same URL locally:"
  echo ""
  echo "  ssh -N -L ${port}:127.0.0.1:${port} USER@THIS_HOST"
  echo ""
  echo "Keep that ssh session open, open http://127.0.0.1:${port} in your laptop browser."
  echo "Bootstrap invite links printed above work unchanged through the tunnel."
  echo "---------------------------------------------------------------------------"
}
