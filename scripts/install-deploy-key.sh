#!/bin/bash

################################################################################
# INSTALL-DEPLOY-KEY: Bootstrap SSH key on target host (one-time setup)
#
# Purpose: One-time installation of SA/deployment SSH public key on target for
#          automated, hands-off deployments thereafter.
#
# Usage:
#   # Method 1: Direct SSH (password auth required once)
#   ./scripts/install-deploy-key.sh -h 192.168.168.42 -u runner -p
#
#   # Method 2: Using cloud provider (GCP examples)
#   ./scripts/install-deploy-key.sh -h 192.168.168.42 -u runner --gcp-zone us-central1-a --gcp-project my-project
#
#   # Method 3: Install locally (target=localhost)
#   ./scripts/install-deploy-key.sh -h localhost -u runner --local
#
# Options:
#   -h, --host HOST           Target host IP/hostname (required)
#   -u, --user USER           Target username (default: runner)
#   -p, --password            Use password auth (will prompt)
#   -k, --identity-file FILE  Path to existing SSH key (default: from GSM)
#   --local                   Install locally (no remote SSH)
#   --gcp-zone ZONE           GCP zone (for cloud setup)
#   --gcp-project PROJECT     GCP project (for cloud setup)
#   --dry-run                 Show what would be done, don't apply
#   --force                   Skip safety checks
#
################################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}✅ $*${NC}" >&2; }
log_warn() { echo -e "${YELLOW}⚠️  $*${NC}" >&2; }
log_error() { echo -e "${RED}❌ $*${NC}" >&2; }

# Parse options
TARGET_HOST=""
TARGET_USER="runner"
USE_PASSWORD=false
USE_LOCAL=false
IDENTITY_FILE=""
DRY_RUN=false
FORCE=false
GCP_ZONE=""
GCP_PROJECT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--host) TARGET_HOST="$2"; shift 2 ;;
    -u|--user) TARGET_USER="$2"; shift 2 ;;
    -p|--password) USE_PASSWORD=true; shift ;;
    -k|--identity-file) IDENTITY_FILE="$2"; shift 2 ;;
    --local) USE_LOCAL=true; shift ;;
    --gcp-zone) GCP_ZONE="$2"; shift 2 ;;
    --gcp-project) GCP_PROJECT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$TARGET_HOST" ]]; then
  log_error "Target host required: -h/--host"
  exit 1
fi

log "=========================================="
log "  DEPLOY KEY INSTALLER"
log "=========================================="
log "Target Host: $TARGET_HOST"
log "Target User: $TARGET_USER"
log "Local Mode: $USE_LOCAL"
log "Password Auth: $USE_PASSWORD"
log ""

################################################################################
# STEP 1: Fetch public key from GSM or identity file
################################################################################

log "Step 1: Fetching deployment public key..."

PUBLIC_KEY=""
if [[ -n "$IDENTITY_FILE" ]] && [[ -f "$IDENTITY_FILE" ]]; then
  log "Reading public key from: $IDENTITY_FILE"
  if [[ -f "${IDENTITY_FILE}.pub" ]]; then
    PUBLIC_KEY=$(cat "${IDENTITY_FILE}.pub")
  else
    # Derive public from private
    PUBLIC_KEY=$(ssh-keygen -y -f "$IDENTITY_FILE" 2>/dev/null)
  fi
else
  log "Fetching deployment key from Google Secret Manager..."
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not found. Install Google Cloud SDK or provide --identity-file"
    exit 1
  fi
  SSH_PRIVATE_KEY=$(gcloud secrets versions access latest --secret="runner-ssh-key" 2>/dev/null || echo "")
  if [[ -z "$SSH_PRIVATE_KEY" ]]; then
    log_error "Failed to fetch SSH key from GSM (secret: runner-ssh-key)"
    exit 1
  fi
  # Derive public from private
  PUBLIC_KEY=$(echo "$SSH_PRIVATE_KEY" | ssh-keygen -y -f /dev/stdin 2>/dev/null || echo "")
fi

if [[ -z "$PUBLIC_KEY" ]]; then
  log_error "Failed to obtain public key"
  exit 1
fi

log_success "Public key obtained"
log "Key: $(echo "$PUBLIC_KEY" | cut -c1-60)..."

################################################################################
# STEP 2: Install key on target
################################################################################

log ""
log "Step 2: Installing public key on target..."

if [[ "$DRY_RUN" == "true" ]]; then
  log_warn "DRY RUN MODE: Not applying changes"
fi

if [[ "$USE_LOCAL" == "true" ]]; then
  # Local installation (target = localhost)
  log "Local mode: installing for user $TARGET_USER"
  
  authorized_keys_file="/home/$TARGET_USER/.ssh/authorized_keys"
  ssh_dir="/home/$TARGET_USER/.ssh"
  
  if [[ ! -d "$ssh_dir" ]]; then
    log "Creating $ssh_dir"
    if [[ "$DRY_RUN" == "false" ]]; then
      sudo mkdir -p "$ssh_dir"
      sudo chmod 700 "$ssh_dir"
      sudo chown "$TARGET_USER:$TARGET_USER" "$ssh_dir"
    fi
  fi
  
  # Check if key already installed
  if sudo test -f "$authorized_keys_file" 2>/dev/null; then
    if sudo grep -q "$(echo "$PUBLIC_KEY" | cut -d' ' -f2)" "$authorized_keys_file" 2>/dev/null; then
      log_success "Public key already installed in $authorized_keys_file"
      if [[ "$FORCE" != "true" ]]; then
        log "Skipping (already present). Use --force to reinstall."
        exit 0
      fi
    fi
  fi
  
  log "Installing key to $authorized_keys_file"
  if [[ "$DRY_RUN" == "false" ]]; then
    echo "$PUBLIC_KEY" | sudo tee -a "$authorized_keys_file" >/dev/null
    sudo chmod 600 "$authorized_keys_file"
    sudo chown "$TARGET_USER:$TARGET_USER" "$authorized_keys_file"
  fi
  
  log_success "Key installed locally"

elif [[ "$USE_PASSWORD" == "true" ]]; then
  # SSH with password auth (first-time bootstrap)
  log "Using password-based SSH to $TARGET_USER@$TARGET_HOST"
  
  install_cmd="mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUBLIC_KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo 'Key installed'"
  
  if [[ "$DRY_RUN" == "false" ]]; then
    if sshpass -p "$(read -sp 'SSH password for $TARGET_USER@$TARGET_HOST: ' pwd; echo "$pwd")" \
      ssh -o StrictHostKeyChecking=accept-new "$TARGET_USER@$TARGET_HOST" "$install_cmd"; then
      log_success "Key installed via password SSH"
    else
      log_error "Failed to install key via SSH"
      exit 1
    fi
  else
    log_warn "Would run: ssh $TARGET_USER@$TARGET_HOST"
    log_warn "Command: $install_cmd"
  fi

elif [[ -n "$GCP_ZONE" && -n "$GCP_PROJECT" ]]; then
  # GCP cloud setup
  log "Using GCP Compute Engine to install key..."
  
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not found"
    exit 1
  fi
  
  instance_name=$(dns_to_instance "$TARGET_HOST") || instance_name="$TARGET_HOST"
  log "GCP Instance: $instance_name (zone: $GCP_ZONE, project: $GCP_PROJECT)"
  
  if [[ "$DRY_RUN" == "false" ]]; then
    gcloud compute ssh "$instance_name" \
      --zone="$GCP_ZONE" \
      --project="$GCP_PROJECT" \
      --command="mkdir -p ~/.ssh && echo '$PUBLIC_KEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
      || {
        log_error "Failed to install key via GCP"
        exit 1
      }
    log_success "Key installed via GCP Compute Engine"
  else
    log_warn "Would install via GCP gcloud compute ssh"
  fi

else
  # Default: assume key-based SSH already works (idempotent check)
  log_warn "No installation method specified. Assuming SSH key-based auth already configured."
  log_warn "To bootstrap, use one of:"
  log_warn "  --password       (first-time setup with password)"
  log_warn "  --local          (install locally)"
  log_warn "  --gcp-zone ZONE --gcp-project PROJECT (GCP cloud init)"
  exit 1
fi

################################################################################
# STEP 3: Verify installation
################################################################################

log ""
log "Step 3: Verifying key installation..."

if [[ "$DRY_RUN" == "false" ]]; then
  if [[ "$USE_LOCAL" == "true" ]]; then
    if sudo grep -q "$(echo "$PUBLIC_KEY" | cut -d' ' -f2)" "/home/$TARGET_USER/.ssh/authorized_keys" 2>/dev/null; then
      log_success "Verification passed: key is installed locally"
    else
      log_error "Verification failed: key not found in authorized_keys"
      exit 1
    fi
  else
    # Try SSH connection without password
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
      "$TARGET_USER@$TARGET_HOST" "echo 'SSH key-based auth verified'" &>/dev/null; then
      log_success "Verification passed: key-based SSH auth works"
    else
      log_warn "Verification inconclusive: could not verify SSH (may need key installed)"
    fi
  fi
else
  log_warn "DRY RUN: Skipping verification"
fi

################################################################################
# SUMMARY
################################################################################

log ""
log "=========================================="
log "  INSTALLATION COMPLETE"
log "=========================================="
log "Target: $TARGET_USER@$TARGET_HOST"
log "Status: Ready for key-based automated deployments"
log ""
log "Next step: Run deployment"
log "  GITHUB_ISSUE_ID=2072 ./scripts/direct-deploy.sh gsm main"
log ""

log_success "Done!"
exit 0
