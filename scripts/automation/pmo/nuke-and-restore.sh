#!/usr/bin/env bash
set -euo pipefail

SSH_KEY=""
#!/usr/bin/env bash
set -euo pipefail

# Controlled nuke and immutable restore helper
# Usage: nuke-and-restore.sh --target 192.168.168.42 --user cloud [--confirm] [--key /path/to/private]
# By default runs in dry-run mode. Passing --confirm performs destructive actions.

TARGET_HOST="192.168.168.42"
TARGET_USER="cloud"
DRY_RUN=true
SSH_KEY=""
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
REMOTE_BACKUP_DIR="/tmp/remote-backups"

show_usage() {
  cat <<EOF
Usage: $0 [--target HOST] [--user USER] [--key /path/to/private_key] [--confirm]

  --target    Target host (default: 192.168.168.42)
  --user      SSH user to connect as (default: cloud)
  --key       Private key to use for SSH/SCP (optional)
  --confirm   Execute destructive actions (required to perform restore)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET_HOST="$2"; shift 2;;
    --user) TARGET_USER="$2"; shift 2;;
    --key) SSH_KEY="$2"; shift 2;;
    --confirm) DRY_RUN=false; shift;;
    --help) show_usage; exit 0;;
    *) echo "Unknown arg: $1"; show_usage; exit 2;;
  esac
done

REMOTE_BASE="/home/${TARGET_USER}/runnercloud"

# Build SSH and SCP commands
SSH_OPTS=( -o BatchMode=yes -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no )
if [[ -n "$SSH_KEY" ]]; then
  SSH_CMD=(ssh -i "$SSH_KEY" "${SSH_OPTS[@]}")
  SCP_CMD=(scp -i "$SSH_KEY" "${SSH_OPTS[@]}")
else
  SSH_CMD=(ssh "${SSH_OPTS[@]}")
  SCP_CMD=(scp "${SSH_OPTS[@]}")
fi

echo "nuke-and-restore: target=$TARGET_HOST user=$TARGET_USER dry_run=$DRY_RUN"

echo "Checking SSH connectivity..."
if ! "${SSH_CMD[@]}" "$TARGET_USER@$TARGET_HOST" 'echo OK' >/dev/null 2>&1; then
  echo "ERROR: cannot SSH to $TARGET_USER@$TARGET_HOST; aborting"
  exit 3
fi

echo "Creating remote backup (safe)"
"${SSH_CMD[@]}" "$TARGET_USER@$TARGET_HOST" "mkdir -p $REMOTE_BACKUP_DIR && tar -czf $REMOTE_BACKUP_DIR/runnercloud-before-$(date +%s).tar.gz -C /home/$TARGET_USER runnercloud || true"

if [[ "$DRY_RUN" == true ]]; then
  cat <<-DRY
DRY RUN: the following actions would be performed when --confirm is supplied:
  - Stop runner services and app processes on $TARGET_HOST
  - Move current deployment to a timestamped backup on the remote host
  - SCP fresh deployment files and restore artifacts from the repository
  - Reconfigure env files and start services using systemd and the deploy script
  - Verify endpoints (http://$TARGET_HOST:3919, metrics etc.)
DRY
  echo "Planned SCP commands (dry-run):"
  echo "${SCP_CMD[@]} -r $REPO_ROOT/ElevatedIQ-Mono-Repo/apps/portal/dist $TARGET_USER@$TARGET_HOST:$REMOTE_BASE/portal/dist"
  echo "${SCP_CMD[@]} -r $REPO_ROOT/services $TARGET_USER@$TARGET_HOST:$REMOTE_BASE/"
  echo "${SCP_CMD[@]} -r $REPO_ROOT/scripts/automation/pmo $TARGET_USER@$TARGET_HOST:$REMOTE_BASE/scripts/automation/"
  exit 0
fi

echo "CONFIRMED: performing controlled nuke and restore"

# Stop services (best-effort) with sudo where required
"${SSH_CMD[@]}" "$TARGET_USER@$TARGET_HOST" bash <<'REMOTE'
set -euo pipefail
sudo pkill -f 'http-server' || true
sudo pkill -f 'node' || true
sudo systemctl --no-pager stop actions-runner.service || true
sleep 2
REMOTE

# Backup current deployment
"${SSH_CMD[@]}" "$TARGET_USER@$TARGET_HOST" "mkdir -p $REMOTE_BACKUP_DIR && sudo mv $REMOTE_BASE $REMOTE_BACKUP_DIR/runnercloud-$(date +%s) || true"

# Ensure target directories exist before copying
"${SSH_CMD[@]}" "$TARGET_USER@$TARGET_HOST" "mkdir -p $REMOTE_BASE/portal/dist $REMOTE_BASE/services $REMOTE_BASE/scripts/automation && sudo chown -R $TARGET_USER:$TARGET_USER $REMOTE_BASE || true"

echo "Copying deployment files to $TARGET_HOST:$REMOTE_BASE"
"${SCP_CMD[@]}" -r "$REPO_ROOT/ElevatedIQ-Mono-Repo/apps/portal/dist" "$TARGET_USER@$TARGET_HOST:$REMOTE_BASE/portal/dist" || true
"${SCP_CMD[@]}" -r "$REPO_ROOT/services" "$TARGET_USER@$TARGET_HOST:$REMOTE_BASE/" || true
"${SCP_CMD[@]}" -r "$REPO_ROOT/scripts/automation/pmo" "$TARGET_USER@$TARGET_HOST:$REMOTE_BASE/scripts/automation/" || true

# Re-create configuration and start services via the provided deploy script
echo "Running remote deployment script"
"${SSH_CMD[@]}" "$TARGET_USER@$TARGET_HOST" bash -s -- "$TARGET_USER" <<'REMOTE2'
set -euo pipefail
REMOTE_USER="$1"
export TARGET_HOST=localhost
export TARGET_USER="$REMOTE_USER"
cd /home/$REMOTE_USER/runnercloud/scripts/automation/pmo || true
if [[ -f deploy-full-stack.sh ]]; then
  bash deploy-full-stack.sh --stage stage3 || true
  bash deploy-full-stack.sh --stage stage4 || true
else
  echo "deploy-full-stack.sh not found; skipping automated start"
fi
REMOTE2

echo "Restore complete — run validation checks or the smoke tests next"

echo "Restore complete — run validation checks or the smoke tests next"
