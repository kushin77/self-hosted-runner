#!/usr/bin/env bash
set -euo pipefail

# restore_from_github.sh
# Idempotent bootstrap to install GitLab CE (optional), restore encrypted secrets and DB,
# and import projects from a GitHub mirror. All credentials are supplied via env vars.

usage(){
  cat <<EOF
Usage: RESTORE_S3_BUCKET=... GITHUB_BACKUP_URL=... GITLAB_DOMAIN=... \
  ./bootstrap/restore_from_github.sh

Environment variables (recommended):
  GITHUB_BACKUP_URL     - git clone URL (mirror) for GitHub backup (required)
  GITLAB_DOMAIN         - domain for new GitLab instance (required)
  GITLAB_ROOT_PASSWORD  - initial root password to set (optional)
  RESTORE_S3_BUCKET     - s3://bucket/path where encrypted backups live (optional)
  DECRYPT_CMD           - command to decrypt backups (e.g. "sops -d" or "age -d -i key.age")
  INSTALL_GITLAB        - if set to "yes", installs GitLab Omnibus (default: yes)
  AWS_PROFILE/AWS_REGION - used if RESTORE_S3_BUCKET is set and aws CLI available

Examples:
  GITHUB_BACKUP_URL="https://github.com/org/repo.git" GITLAB_DOMAIN="gitlab.example.com" \
    RESTORE_S3_BUCKET="s3://backups/gitlab" ./bootstrap/restore_from_github.sh

EOF
}

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
  usage
  exit 0
fi

if [ -z "${GITHUB_BACKUP_URL:-}" ] || [ -z "${GITLAB_DOMAIN:-}" ]; then
  echo "ERROR: GITHUB_BACKUP_URL and GITLAB_DOMAIN must be set"
  usage
  exit 2
fi

INSTALL_GITLAB=${INSTALL_GITLAB:-yes}

log(){ echo "[restore] $*"; }

# 1. Optionally install GitLab Omnibus (idempotent)
if [ "$INSTALL_GITLAB" = "yes" ]; then
  if ! command -v gitlab-ctl >/dev/null 2>&1; then
    log "Installing GitLab CE (Omnibus)..."
    curl -s https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash
    sudo EXTERNAL_URL="https://${GITLAB_DOMAIN}" apt-get update -y
    sudo EXTERNAL_URL="https://${GITLAB_DOMAIN}" apt-get install -y gitlab-ce
    log "GitLab package install invoked. Waiting for services to stabilize..."
    sleep 30
  else
    log "GitLab appears already installed; skipping package install."
  fi
fi

# 2. Restore encrypted files from S3 (if provided) or expect local files
TEMP_DIR=$(mktemp -d)
cleanup(){ rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

if [ -n "${RESTORE_S3_BUCKET:-}" ]; then
  if command -v aws >/dev/null 2>&1; then
    log "Downloading backups from ${RESTORE_S3_BUCKET}..."
    aws s3 cp --recursive "${RESTORE_S3_BUCKET}" "$TEMP_DIR/" || true
  else
    log "AWS CLI not found; cannot download from S3. Skipping S3 fetch."
  fi
fi

# Decrypt helper
decrypt_file(){
  local src="$1" dst="$2"
  if [ -z "${DECRYPT_CMD:-}" ]; then
    if command -v sops >/dev/null 2>&1; then
      DECRYPT_CMD="sops -d"
    elif command -v age >/dev/null 2>&1 && [ -n "${AGE_KEY_FILE:-}" ]; then
      DECRYPT_CMD="age -d -i ${AGE_KEY_FILE}"
    else
      log "No decryption command available; assuming plaintext for $src"
      cp "$src" "$dst"
      return 0
    fi
  fi
  log "Decrypting $src -> $dst"
  eval "$DECRYPT_CMD < \"$src\" > \"$dst\""
}

# 3. Restore gitlab.rb and secrets if present
if [ -f "$TEMP_DIR/gitlab-secrets.json" ] || [ -f "/etc/gitlab/gitlab-secrets.json" ]; then
  if [ -f "$TEMP_DIR/gitlab-secrets.json" ]; then
    log "Restoring gitlab-secrets.json from backup"
    sudo cp "$TEMP_DIR/gitlab-secrets.json" /etc/gitlab/gitlab-secrets.json
  else
    log "No backup gitlab-secrets.json found in S3 temp; leaving existing file."
  fi
fi

if [ -f "$TEMP_DIR/gitlab.rb" ]; then
  log "Restoring /etc/gitlab/gitlab.rb from backup"
  sudo cp "$TEMP_DIR/gitlab.rb" /etc/gitlab/gitlab.rb
fi

# 4. Reconfigure GitLab
if command -v gitlab-ctl >/dev/null 2>&1; then
  log "Running gitlab-ctl reconfigure"
  sudo gitlab-ctl reconfigure || true
fi

# 5. Restore DB backup if present
if ls "$TEMP_DIR"/*.tar 1> /dev/null 2>&1; then
  LATEST_BACKUP=$(ls -1t "$TEMP_DIR"/*.tar | head -n1)
  log "Found backup $LATEST_BACKUP. Restoring to /var/opt/gitlab/backups/ and invoking gitlab-backup restore"
  sudo cp "$LATEST_BACKUP" /var/opt/gitlab/backups/
  # extract timestamp from filename
  BACKUP_BASENAME=$(basename "$LATEST_BACKUP")
  BACKUP_TIMESTAMP=${BACKUP_BASENAME%%.tar}
  sudo gitlab-backup restore BACKUP=$BACKUP_TIMESTAMP || true
fi

# 6. Ensure GitLab root user password is set (if provided)
if [ -n "${GITLAB_ROOT_PASSWORD:-}" ]; then
  if command -v gitlab-rails >/dev/null 2>&1; then
    log "Setting root password via gitlab-rails"
    sudo gitlab-rails runner "user = User.where(id: 1).first; if user; user.password='${GITLAB_ROOT_PASSWORD}'; user.password_confirmation='${GITLAB_ROOT_PASSWORD}'; user.save!; end"
  else
    log "gitlab-rails not found; skip setting root password"
  fi
fi

# 7. Import projects from GitHub mirror (mirror clone -> push --mirror)
TMP_MIRROR="$TEMP_DIR/mirror.git"
log "Cloning mirror from ${GITHUB_BACKUP_URL}"
git clone --mirror "${GITHUB_BACKUP_URL}" "$TMP_MIRROR" || true

if [ -d "$TMP_MIRROR" ]; then
  log "Preparing to push mirror into GitLab. Creating project via API if possible."
  if [ -n "${GITLAB_API_TOKEN:-}" ]; then
    log "Using provided GITLAB_API_TOKEN to create/import projects (best-effort)."
    # try to create a project named same as repo
    REPO_NAME=$(basename -s .git "$GITHUB_BACKUP_URL")
    NAMESPACE=${GITLAB_NAMESPACE:-root}
    curl -s --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" --data "name=${REPO_NAME}&path=${REPO_NAME}&namespace_id=1&visibility=private" "https://${GITLAB_DOMAIN}/api/v4/projects" || true
    TARGET_URL="https://${GITLAB_DOMAIN}/${NAMESPACE}/${REPO_NAME}.git"
  else
    log "No GITLAB_API_TOKEN provided. You must create target project first and set GITLAB_TARGET_URL to push into."
    TARGET_URL=${GITLAB_TARGET_URL:-}
  fi

  if [ -z "${TARGET_URL:-}" ]; then
    log "Skipping automatic push: no TARGET_URL available. To push manually: cd $TMP_MIRROR && git push --mirror <target-url>"
  else
    log "Pushing mirror to ${TARGET_URL}"
    (cd "$TMP_MIRROR" && git remote set-url --push origin "$TARGET_URL" && git push --mirror origin) || true
  fi
fi

log "Restore script completed. Verify GitLab UI at https://${GITLAB_DOMAIN} and re-register runners as needed."
