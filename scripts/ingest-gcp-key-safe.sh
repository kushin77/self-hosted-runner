#!/usr/bin/env bash
set -euo pipefail

# Safe helper to validate and ingest a GCP service account JSON into GitHub Actions
# Usage: cat key.json | ./scripts/ingest-gcp-key-safe.sh --repo owner/repo --secret-name GCP_SERVICE_ACCOUNT_KEY

REPO=""
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
usage() {
  cat <<EOF
Usage: cat key.json | $0 --repo owner/repo [--secret-name NAME]

This script reads a GCP service account JSON from stdin, validates it with jq,
and (optionally) uploads it to GitHub Actions secrets using gh.

It does NOT store the secret locally.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --secret-name) SECRET_NAME="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "--repo is required" >&2
  usage
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required. Install jq and retry." >&2
  exit 2
fi

TMPFILE=$(mktemp)
trap 'shred -u "$TMPFILE" 2>/dev/null || rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE"

if ! jq empty "$TMPFILE" 2>/dev/null; then
  echo "ERROR: Provided file is not valid JSON." >&2
  head -c 200 "$TMPFILE" >&2 || true
  exit 3
fi

TYPE=$(jq -r '.type // empty' "$TMPFILE")
PROJECT_ID=$(jq -r '.project_id // empty' "$TMPFILE")

if [[ "$TYPE" != "service_account" ]]; then
  echo "ERROR: JSON 'type' is not 'service_account' (found: '$TYPE')." >&2
  echo "This looks like the wrong file or a truncated key." >&2
  exit 4
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: 'project_id' field missing or empty." >&2
  exit 5
fi

echo "Validated GCP service account JSON (project_id=$PROJECT_ID)."

read -p "Proceed to upload to GitHub Actions secrets for repo '$REPO' as '$SECRET_NAME'? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted by user." && exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI required to upload secret. Install gh and auth before running." >&2
  exit 6
fi

echo "Uploading secret to $REPO..."
gh secret set "$SECRET_NAME" --repo "$REPO" --body-file "$TMPFILE"

echo "Secret uploaded. Please verify via repository settings or run the verification workflow." 
