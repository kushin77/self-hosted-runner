#!/usr/bin/env bash
set -euo pipefail

# Verify required Google Secret Manager secrets exist and are not placeholder values.
# Usage: PROJECT=nexusshield-prod ./scripts/ci/verify_gsm_secrets.sh

PROJECT=${PROJECT:-nexusshield-prod}
SECRETS=(
  github-token
  aws-access-key-id
  aws-secret-access-key
  VAULT_TOKEN
  terraform-signing-key
)

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
missing=0

for s in "${SECRETS[@]}"; do
  echo -n "Checking secret: $s... "
  if ! gcloud secrets versions access latest --secret="$s" --project="$PROJECT" >"$tmpfile" 2>/dev/null; then
    echo "MISSING"
    missing=1
    continue
  fi
  val=$(tr -d '\r' <"$tmpfile")
  if [[ -z "$val" || "$val" =~ placeholder|s\.your|ghp_XXXXXXXXXXXXXXXX|ghp_XXXX|YOUR_GITHUB_TOKEN ]]; then
    echo "INVALID_PLACEHOLDER"
    missing=1
  else
    echo "OK"
  fi
done

if [[ $missing -ne 0 ]]; then
  echo "One or more secrets missing or invalid in Secret Manager. Populate required secrets and retry." >&2
  exit 2
fi

echo "All required GSM secrets present and non-placeholder (project=$PROJECT)."
