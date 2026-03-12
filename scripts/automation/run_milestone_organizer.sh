#!/usr/bin/env bash
set -euo pipefail

# Wrapper to run the milestone organizer in automated, idempotent, hands-off mode.
# - Uses `gh` (requires auth). Attempts to source token from credential helpers.
# - Writes append-only audit artifacts to `artifacts/milestones-assignments/`.

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "kushin77/self-hosted-runner")"
ARTIFACT_DIR="artifacts/milestones-assignments"
mkdir -p "$ARTIFACT_DIR"
TS=$(date -u +%Y%m%dT%H%M%SZ)
OPEN_JSON="$ARTIFACT_DIR/open_$TS.json"
CLOSED_JSON="$ARTIFACT_DIR/closed_$TS.json"
AUDIT_LOG="$ARTIFACT_DIR/assignments_$TS.jsonl"

echo "Repo: $REPO"
echo "Artifact dir: $ARTIFACT_DIR"
LOCKFILE=${LOCKFILE:-/tmp/milestone_organizer.lock}

# Acquire non-blocking flock to avoid concurrent runs
exec 9>"$LOCKFILE" || exit 1
if ! flock -n 9; then
  echo "Another organizer run is in progress; exiting"; exit 0
fi

# Ensure gh auth available; try helper fallbacks (GSM/Vault/KMS helpers should set GH_TOKEN)
if gh auth status >/dev/null 2>&1; then
  echo "gh: authenticated"
else
  echo "gh: not authenticated — attempting credential helpers"
  if [ -x scripts/utilities/credcache.sh ]; then
    echo "Attempting scripts/utilities/credcache.sh get gh_token"
    GH_TOKEN=$(scripts/utilities/credcache.sh get gh_token 2>/dev/null || true)
    if [ -n "${GH_TOKEN:-}" ]; then
      echo "Using GH_TOKEN from credcache"
      echo "$GH_TOKEN" | gh auth login --with-token || true
    fi
  fi
fi

echo "Running organizer (apply) — idempotent"
if ! scripts/utilities/organize_milestones.sh --apply; then
  echo "organizer exited with non-zero status"; rc=$?; \
  gh issue create --title "milestone-organizer: run failure" --body "Organizer exited with status $rc. See artifacts in $ARTIFACT_DIR" || true; \
  exit $rc
fi

echo "Exporting current issue state to artifacts"
gh issue list --state open --limit 1000 --json number,title,milestone > "$OPEN_JSON" || true
gh issue list --state closed --limit 1000 --json number,title,milestone > "$CLOSED_JSON" || true

# Build append-only JSONL audit: one JSON object per line
jq -c '.[] | {state: "open", number: .number, title: .title, milestone: (.milestone|.title // null)}' "$OPEN_JSON" > "$AUDIT_LOG" || true
jq -c '.[] | {state: "closed", number: .number, title: .title, milestone: (.milestone|.title // null)}' "$CLOSED_JSON" >> "$AUDIT_LOG" || true

echo "Wrote audit log: $AUDIT_LOG"
echo "Done"

# Optional archival: upload artifacts to S3 or GCS if configured via env vars.
ARCHIVE_S3_BUCKET=${ARCHIVE_S3_BUCKET:-}
ARCHIVE_GCS_BUCKET=${ARCHIVE_GCS_BUCKET:-}
ARCHIVE_PREFIX=${ARCHIVE_PREFIX:-milestones-assignments}

upload_to_s3() {
  local file=$1
  local key="$ARCHIVE_PREFIX/$(basename "$file")"
  if command -v aws >/dev/null 2>&1; then
    echo "Uploading $file -> s3://$ARCHIVE_S3_BUCKET/$key"
    aws s3 cp "$file" "s3://$ARCHIVE_S3_BUCKET/$key" --only-show-errors || echo "s3 upload failed for $file"
  else
    echo "aws CLI not available; skipping S3 upload"
  fi
}

upload_to_gcs() {
  local file=$1
  local dest="gs://$ARCHIVE_GCS_BUCKET/$ARCHIVE_PREFIX/$(basename "$file")"
  if command -v gsutil >/dev/null 2>&1; then
    echo "Uploading $file -> $dest"
    gsutil cp "$file" "$dest" || echo "gcs upload failed for $file"
  else
    echo "gsutil not available; skipping GCS upload"
  fi
}

if [ -n "$ARCHIVE_S3_BUCKET" ] || [ -n "$ARCHIVE_GCS_BUCKET" ]; then
  echo "Archival configured: S3=$ARCHIVE_S3_BUCKET GCS=$ARCHIVE_GCS_BUCKET"
  for f in "$OPEN_JSON" "$CLOSED_JSON" "$AUDIT_LOG"; do
    if [ -f "$f" ]; then
      if [ -n "$ARCHIVE_S3_BUCKET" ]; then
        upload_to_s3 "$f"
      fi
      if [ -n "$ARCHIVE_GCS_BUCKET" ]; then
        upload_to_gcs "$f"
      fi
      # write checksum next to file and upload as well
      shasum -a 256 "$f" | awk '{print $1}' > "$f.sha256"
      if [ -n "$ARCHIVE_S3_BUCKET" ]; then upload_to_s3 "$f.sha256"; fi
      if [ -n "$ARCHIVE_GCS_BUCKET" ]; then upload_to_gcs "$f.sha256"; fi
    fi
  done
else
  echo "No archival target configured; skipping upload step"
fi
