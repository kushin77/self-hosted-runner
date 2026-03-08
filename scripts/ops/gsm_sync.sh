#!/usr/bin/env bash
set -euo pipefail

# gsm_sync.sh
# Helper to sync secrets from GCP Secret Manager into GitHub Actions repository secrets
# Usage:
#   ./scripts/ops/gsm_sync.sh --project my-gcp-project --repo owner/repo secret1 secret2 ...
# Requires: `gcloud` authenticated (service account or workload identity) and `gh` CLI authenticated

print_usage() {
  cat <<EOF
Usage: $0 --project PROJECT --repo OWNER/REPO SECRET_NAME [SECRET_NAME ...]

Fetches secrets from GCP Secret Manager and writes them to GitHub Actions repository secrets
Requires: gcloud + gh CLI, and appropriate permissions:
 - gcloud principal: roles/secretmanager.secretAccessor
 - gh CLI token: repo

Examples:
  $0 --project my-project --repo kushin77/self-hosted-runner SLACK_WEBHOOK_URL PAGERDUTY_SERVICE_KEY
EOF
}

if [ "$#" -lt 1 ]; then
  print_usage
  exit 1
fi

PROJECT=""
REPO=""
SECRETS=()

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT="$2"; shift 2;;
    --repo)
      REPO="$2"; shift 2;;
    --help|-h)
      print_usage; exit 0;;
    *)
      SECRETS+=("$1"); shift;;
  esac
done

if [ -z "$PROJECT" ] || [ -z "$REPO" ] || [ ${#SECRETS[@]} -eq 0 ]; then
  echo "Error: missing required args"
  print_usage
  exit 2
fi

echo "GSM sync starting: project=$PROJECT repo=$REPO secrets=${SECRETS[*]}"

for s in "${SECRETS[@]}"; do
  echo "Fetching secret: $s"
  # fetch the latest version from GCP Secret Manager
  val=$(gcloud secrets versions access latest --project "$PROJECT" --secret "$s" 2>/dev/null || true)
  if [ -z "$val" ]; then
    echo "Warning: secret '$s' not found in project $PROJECT - skipping"
    continue
  fi

  # write to a temp file and set GitHub repo secret via gh CLI
  tmpf=$(mktemp)
  printf "%s" "$val" > "$tmpf"
  echo "Setting repository secret $s for $REPO"
  gh secret set "$s" --repo "$REPO" --body-file "$tmpf"
  rm -f "$tmpf"
  echo "Secret $s synced"
done

echo "GSM sync complete"
