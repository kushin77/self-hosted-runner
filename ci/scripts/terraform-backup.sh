#!/bin/bash
# Terraform State Backup Script
# Purpose: Create timestamped backups of terraform state before apply operations
# Usage: ./terraform-backup.sh [--upload] [--encrypt] [--destination PATH]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_DIR="${TERRAFORM_DIR:-.}/terraform"
BACKUP_DIR="${BACKUP_DIR:-.}/terraform-backups"
UPLOAD_TO_GCS="${UPLOAD_TO_GCS:-false}"
ENCRYPT_BACKUP="${ENCRYPT_BACKUP:-false}"
GCS_BUCKET="${GCS_BUCKET:-""}"
GCP_PROJECT="${GCP_PROJECT:-gcp-eiq}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%dT%H%M%SZ)

# Flags
UPLOAD_FLAG=false
ENCRYPT_FLAG=false
CUSTOM_DEST=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --upload)
      UPLOAD_FLAG=true
      shift
      ;;
    --encrypt)
      ENCRYPT_FLAG=true
      shift
      ;;
    --destination)
      CUSTOM_DEST="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Validate terraform directory
if [ ! -d "$TERRAFORM_DIR" ]; then
  log_error "Terraform directory not found: $TERRAFORM_DIR"
  exit 1
fi

# Create backup directory
if [ ! -d "$BACKUP_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
  log_info "Created backup directory: $BACKUP_DIR"
fi

# Check for terraform state file
STATE_FILE="$TERRAFORM_DIR/terraform.tfstate"
if [ ! -f "$STATE_FILE" ]; then
  log_warning "No local terraform.tfstate found at $STATE_FILE"
  log_info "Attempting to initialize terraform to fetch state..."
  cd "$TERRAFORM_DIR"
  terraform init -input=false -upgrade || {
    log_error "Failed to initialize terraform"
    exit 1
  }
  cd - > /dev/null
fi

log_info "Starting terraform state backup..."

# Create Backup
BACKUP_FILE="$BACKUP_DIR/terraform-state-backup-${TIMESTAMP}.tfstate"
cp "$STATE_FILE" "$BACKUP_FILE" || {
  log_error "Failed to create state backup"
  exit 1
}
log_success "State backup created: $BACKUP_FILE"

# Create backup metadata
METADATA_FILE="$BACKUP_DIR/terraform-state-backup-${TIMESTAMP}.metadata.json"
cat > "$METADATA_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "backup_file": "$(basename $BACKUP_FILE)",
  "terraform_version": "$(cd $TERRAFORM_DIR && terraform version -json | jq -r '.terraform_version')",
  "state_size_bytes": $(stat -f%z "$STATE_FILE" 2>/dev/null || stat -c%s "$STATE_FILE"),
  "hostname": "$(hostname)",
  "user": "$(whoami)",
  "git_sha": "$(cd "$(dirname $TERRAFORM_DIR)" && git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "git_branch": "$(cd "$(dirname $TERRAFORM_DIR)" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
}
EOF
log_success "Metadata saved: $METADATA_FILE"

# Extract resource count from state
RESOURCE_COUNT=$(jq '.resources | length' "$STATE_FILE" 2>/dev/null || echo "unknown")
log_info "State contains approximately $RESOURCE_COUNT resources"

# Encrypt backup if requested
if [ "$ENCRYPT_FLAG" = true ]; then
  log_info "Encrypting backup..."
  if command -v gpg &> /dev/null; then
    gpg --symmetric --cipher-algo AES256 --output "$BACKUP_FILE.gpg" "$BACKUP_FILE" || {
      log_error "Failed to encrypt backup"
      exit 1
    }
    shred -vfz -n 3 "$BACKUP_FILE" 2>/dev/null || rm -f "$BACKUP_FILE"
    BACKUP_FILE="$BACKUP_FILE.gpg"
    log_success "Backup encrypted: $BACKUP_FILE"
  else
    log_warning "GPG not found; skipping encryption"
  fi
fi

# Upload to GCS if requested or flag is set
if [ "$UPLOAD_FLAG" = true ] || [ "$UPLOAD_TO_GCS" = true ]; then
  if [ -z "$GCS_BUCKET" ]; then
    log_warning "GCS_BUCKET not set; skipping upload"
  else
    log_info "Uploading backup to GCS..."
    if command -v gsutil &> /dev/null; then
      GCS_PATH="gs://$GCS_BUCKET/terraform-backups/${TIMESTAMP}/"
      gsutil -m cp "$BACKUP_FILE" "$METADATA_FILE" "$GCS_PATH" || {
        log_error "Failed to upload to GCS"
        exit 1
      }
      log_success "Backup uploaded to $GCS_PATH"
    else
      log_error "gsutil not found; cannot upload to GCS"
      exit 1
    fi
  fi
fi

# Cleanup old backups (local)
log_info "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "terraform-state-backup-*.tfstate*" -type f -mtime +$RETENTION_DAYS -delete || true
DELETED_COUNT=$(find "$BACKUP_DIR" -name "terraform-state-backup-*.tfstate*" -type f -mtime +$RETENTION_DAYS | wc -l)
log_info "Removed $DELETED_COUNT old backups"

# Summary
log_success "State backup completed successfully"
echo ""
echo -e "${GREEN}Backup Summary:${NC}"
echo "  Location: $BACKUP_FILE"
echo "  Timestamp: $TIMESTAMP"
echo "  Metadata: $METADATA_FILE"
echo "  Resources: $RESOURCE_COUNT"
echo "  Encrypted: $ENCRYPT_FLAG"
echo "  Uploaded: $([ $UPLOAD_FLAG = true ] || [ $UPLOAD_TO_GCS = true ] && echo 'yes' || echo 'no')"
echo ""

# Return backup file path for use in other scripts
echo "$BACKUP_FILE"
