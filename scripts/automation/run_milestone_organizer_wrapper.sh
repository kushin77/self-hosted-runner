#!/usr/bin/env bash
set -euo pipefail

# Wrapper to source credential helpers before running the organizer
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$SCRIPT_DIR/.."

# Try to load local credcache
if [ -x "$REPO_DIR/scripts/utilities/credcache.sh" ]; then
  echo "Loading credcache..."
  # shellcheck source=/dev/null
  source "$REPO_DIR/scripts/utilities/credcache.sh" || true
  load_credcache || true
fi

# Try GSM/Vault helpers if present
if [ -x "$REPO_DIR/scripts/utilities/gsm_fetch_token.sh" ]; then
  echo "Attempting GSM token fetch (if configured)"
  "$REPO_DIR/scripts/utilities/gsm_fetch_token.sh" "projects/${GSM_PROJECT:-nexusshield-prod}/secrets/GH_TOKEN" "/var/run/secrets/gh_token" || true
  if [ -f /var/run/secrets/gh_token ]; then
    echo "Using GH token from /var/run/secrets/gh_token"
    cat /var/run/secrets/gh_token | gh auth login --with-token || true
  fi
fi

echo "Starting milestone organizer (wrapper)"
exec "$REPO_DIR/scripts/automation/run_milestone_organizer.sh"
