#!/usr/bin/env bash
set -euo pipefail

# gitlab_backup_encrypt.sh
# Creates a GitLab backup, collects /etc/gitlab/gitlab-secrets.json and gitlab.rb,
# encrypts the archive with sops or age, and optionally uploads to S3.

usage(){
  cat <<EOF
Usage: RESTORE_S3_BUCKET=s3://... AGE_RECIPIENT="age1..." ./scripts/backup/gitlab_backup_encrypt.sh

Environment variables:
  BACKUP_RETENTION_DAYS - optional retention housekeeping (not implemented here)
  S3_BUCKET             - s3://bucket/path to upload encrypted backup (optional)
  AGE_RECIPIENT         - age public key recipient to encrypt with (optional)
  SOPS_KMS              - if using sops with KMS/GCP, rely on sops config

Produces a file: ./artifacts/gitlab_backup_<timestamp>.tar.age (or .sops.yaml)
EOF
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage
  exit 0
fi

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT_DIR="${OUT_DIR:-artifacts/backups}"
mkdir -p "$OUT_DIR"

log(){ echo "[backup] $*"; }

if command -v gitlab-backup >/dev/null 2>&1; then
  log "Creating GitLab backup via gitlab-backup create"
  sudo gitlab-backup create STRATEGY=copy || true
else
  log "gitlab-backup not found; skipping backup create (expecting existing backups)."
fi

# find latest backup tar in /var/opt/gitlab/backups
LATEST=$(ls -1t /var/opt/gitlab/backups/*.tar 2>/dev/null || true | head -n1 || true)

TMPDIR=$(mktemp -d)
cleanup(){ rm -rf "$TMPDIR"; }
trap cleanup EXIT

if [ -n "$LATEST" ]; then
  cp "$LATEST" "$TMPDIR/"
  cp /etc/gitlab/gitlab-secrets.json "$TMPDIR/" 2>/dev/null || true
  cp /etc/gitlab/gitlab.rb "$TMPDIR/" 2>/dev/null || true
else
  log "No backup tar found under /var/opt/gitlab/backups; still collecting config files if present."
  cp /etc/gitlab/gitlab-secrets.json "$TMPDIR/" 2>/dev/null || true
  cp /etc/gitlab/gitlab.rb "$TMPDIR/" 2>/dev/null || true
fi

ARCHIVE_NAME="gitlab_backup_${TIMESTAMP}.tar"
tar -C "$TMPDIR" -cf "$OUT_DIR/$ARCHIVE_NAME" .

# Encrypt
if command -v sops >/dev/null 2>&1; then
  log "Encrypting with sops -> ${ARCHIVE_NAME}.sops"
  sops --encrypt --output "$OUT_DIR/${ARCHIVE_NAME}.sops" "$OUT_DIR/$ARCHIVE_NAME"
  ENCRYPTED="$OUT_DIR/${ARCHIVE_NAME}.sops"
elif [ -n "${AGE_RECIPIENT:-}" ] && command -v age >/dev/null 2>&1; then
  log "Encrypting with age recipient ${AGE_RECIPIENT} -> ${ARCHIVE_NAME}.age"
  age -r "$AGE_RECIPIENT" -o "$OUT_DIR/${ARCHIVE_NAME}.age" "$OUT_DIR/$ARCHIVE_NAME"
  ENCRYPTED="$OUT_DIR/${ARCHIVE_NAME}.age"
else
  log "No sops or age recipient; leaving plaintext archive at $OUT_DIR/$ARCHIVE_NAME"
  ENCRYPTED="$OUT_DIR/$ARCHIVE_NAME"
fi

# Optional upload to S3
if [ -n "${S3_BUCKET:-}" ] && command -v aws >/dev/null 2>&1; then
  log "Uploading $ENCRYPTED to ${S3_BUCKET}"
  aws s3 cp "$ENCRYPTED" "${S3_BUCKET}/$(basename "$ENCRYPTED")"
fi

log "Backup complete: $ENCRYPTED"
