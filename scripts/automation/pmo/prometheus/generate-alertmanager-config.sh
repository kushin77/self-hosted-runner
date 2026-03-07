#!/usr/bin/env bash
set -euo pipefail

# Generates `alertmanager.yml` from `alertmanager.yml.tpl` using the values in `.env` or environment variables.
# Tries `envsubst` first, falls back to a small perl substitution if available.

cd "$(dirname "$0")" || exit 1

if [ ! -f .env ]; then
  # If .env doesn't exist, check if SLACK_WEBHOOK_URL is in environment
  if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
    echo "Error: .env not found in $(pwd) and SLACK_WEBHOOK_URL not in environment. Copy .env.template to .env and populate secrets before running." >&2
    exit 1
  fi
  echo "Using environment variables for config generation (SLACK_WEBHOOK_URL is set)"
else
  # Export variables from .env (ignore comments)
  set -a
  # shellcheck disable=SC2046
  eval $(grep -v '^\s*#' .env | sed -n '/=/p')
  set +a
fi

TEMPLATE=alertmanager.yml.tpl
OUT=alertmanager.yml

if command -v envsubst >/dev/null 2>&1; then
  envsubst < "$TEMPLATE" > "$OUT"
  echo "Generated $OUT using envsubst"
  exit 0
fi

if command -v perl >/dev/null 2>&1; then
  perl -pe 's/\$\{SLACK_WEBHOOK_URL\}/$ENV{SLACK_WEBHOOK_URL}/g; s/\$\{PAGERDUTY_SERVICE_KEY\}/$ENV{PAGERDUTY_SERVICE_KEY}/g;' < "$TEMPLATE" > "$OUT"
  echo "Generated $OUT using perl substitution"
  exit 0
fi

echo "Error: neither envsubst nor perl is available to generate $OUT. Install gettext (envsubst) or perl." >&2
exit 2
