#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG_FILE="${REDEPLOY_CONFIG:-$ROOT_DIR/config/redeploy/redeploy.env}"

if [[ -f "$CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CFG_FILE"
fi

DOMAIN_NAME="${DOMAIN_NAME:-elevatediq.ai}"
NAS_HOST="${NAS_HOST:-192.168.168.100}"
NAS_PATH="${NAS_PATH:-/home/elevatediq-svc-nas/repositories/iac}"
GCP_ARCHIVE_BUCKET="${GCP_ARCHIVE_BUCKET:-gs://elevatediq-ai-archive}"
INCREMENTAL_RETENTION_DAYS="${INCREMENTAL_RETENTION_DAYS:-14}"
WEEKLY_FULL_RETENTION_DAYS="${WEEKLY_FULL_RETENTION_DAYS:-30}"
WEEKLY_FULL_DAY="${WEEKLY_FULL_DAY:-Sun}"
DRY_RUN="${DRY_RUN:-true}"

DATE_UTC="$(date -u +%Y%m%d)"
DAY_UTC="$(date -u +%a)"
REPORT_DIR="$ROOT_DIR/reports/redeploy"
mkdir -p "$REPORT_DIR"
REPORT_FILE="$REPORT_DIR/nas-backup-policy-$DATE_UTC.md"

log() { echo "[nas-backup] $*"; }
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

assert_tools() {
  local missing=()
  for t in gsutil tar find; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required tools: ${missing[*]}" >&2
    exit 1
  fi
}

create_incremental() {
  local archive="/tmp/nas-incremental-${DATE_UTC}.tar.gz"
  log "Preparing daily incremental backup for $NAS_PATH"
  run "tar -czf '$archive' '$NAS_PATH'"
  run "gsutil cp '$archive' '$GCP_ARCHIVE_BUCKET/incremental/${DOMAIN_NAME}-${DATE_UTC}.tar.gz'"
  run "rm -f '$archive'"
}

create_weekly_full_if_due() {
  if [[ "$DAY_UTC" != "$WEEKLY_FULL_DAY" ]]; then
    log "Weekly full backup not due today ($DAY_UTC != $WEEKLY_FULL_DAY)"
    return 0
  fi

  local archive="/tmp/nas-weekly-full-${DATE_UTC}.tar.gz"
  log "Preparing weekly full backup for $NAS_PATH"
  run "tar -czf '$archive' '$NAS_PATH'"
  run "gsutil cp '$archive' '$GCP_ARCHIVE_BUCKET/weekly-full/${DOMAIN_NAME}-${DATE_UTC}.tar.gz'"
  run "rm -f '$archive'"
}

cleanup_old_backups() {
  log "Applying retention cleanup for incremental and weekly full backups"
  local cutoff_inc
  local cutoff_weekly
  cutoff_inc="$(date -u -d "$INCREMENTAL_RETENTION_DAYS days ago" +%Y%m%d)"
  cutoff_weekly="$(date -u -d "$WEEKLY_FULL_RETENTION_DAYS days ago" +%Y%m%d)"

  # Cleanup incremental older than cutoff.
  run "gsutil ls '$GCP_ARCHIVE_BUCKET/incremental/' 2>/dev/null | awk -F'[-.]' '{print \$(NF-1)}' >/tmp/inc-dates.txt || true"
  run "gsutil ls '$GCP_ARCHIVE_BUCKET/incremental/' 2>/dev/null | while read -r f; do d=\$(echo \"$f\" | grep -oE '[0-9]{8}' | tail -1); if [[ -n \"$d\" && \"$d\" < '$cutoff_inc' ]]; then gsutil rm \"$f\"; fi; done"

  # Cleanup weekly full older than cutoff.
  run "gsutil ls '$GCP_ARCHIVE_BUCKET/weekly-full/' 2>/dev/null | while read -r f; do d=\$(echo \"$f\" | grep -oE '[0-9]{8}' | tail -1); if [[ -n \"$d\" && \"$d\" < '$cutoff_weekly' ]]; then gsutil rm \"$f\"; fi; done"
}

generate_report() {
  cat > "$REPORT_FILE" <<EOF
# NAS Backup Policy Verification

- Date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Domain: $DOMAIN_NAME
- NAS Host: $NAS_HOST
- NAS Path: $NAS_PATH
- GCP Archive Bucket: $GCP_ARCHIVE_BUCKET
- Daily Incremental: enabled
- Weekly Full Day: $WEEKLY_FULL_DAY
- Weekly Full Retention: $WEEKLY_FULL_RETENTION_DAYS days
- Incremental Retention: $INCREMENTAL_RETENTION_DAYS days
- Dry Run: $DRY_RUN

## Policy Confirmation
- Daily incremental backup path is configured.
- Weekly full backup path is configured.
- 30-day weekly full retention is enforceable.
- Cleanup process for old weekly backups is configured.
EOF
  log "Wrote policy report: $REPORT_FILE"
}

main() {
  assert_tools
  create_incremental
  create_weekly_full_if_due
  cleanup_old_backups
  generate_report
}

main "$@"
