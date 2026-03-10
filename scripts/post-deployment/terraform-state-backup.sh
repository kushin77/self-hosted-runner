#!/bin/bash

# Terraform State Backup Automation Script
# Purpose: Backup local Terraform state to GCS with versioning & lifecycle policies
# Schedule: Cloud Scheduler (every 6 hours)
# Related Issue: #2260

set -euo pipefail

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
BUCKET_NAME="nexusshield-terraform-state-backups"
TFSTATE_SOURCE="${TFSTATE_SOURCE:-.}/terraform/tfstate"
BACKUP_PREFIX="backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
AUDIT_LOG="logs/terraform-backups/audit.jsonl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Audit trail entry
audit_log_entry() {
    local status=$1
    local message=$2
    local entry=$(cat <<EOF
{"timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","event":"terraform_state_backup","status":"${status}","message":"${message}","bucket":"${BUCKET_NAME}","source":"${TFSTATE_SOURCE}","backup_timestamp":"${TIMESTAMP}"}
EOF
)
    echo "$entry" >> "${AUDIT_LOG}"
}

# Create audit log directory if needed
mkdir -p logs/terraform-backups

log_info "Starting Terraform state backup..."
log_info "Project: $PROJECT_ID"
log_info "Bucket: $BUCKET_NAME"
log_info "Timestamp: $TIMESTAMP"

# Step 1: Ensure bucket exists with versioning
log_info "Checking GCS bucket..."
if ! gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
    log_warn "Bucket does not exist, creating..."
    gsutil mb -p "$PROJECT_ID" "gs://${BUCKET_NAME}"
    gsutil versioning set on "gs://${BUCKET_NAME}"
    log_info "Bucket created with versioning enabled"
fi

# Step 2: Verify versioning is enabled
versioning_status=$(gsutil versioning get "gs://${BUCKET_NAME}" | grep -o "Enabled\|Suspended")
if [ "$versioning_status" != "Enabled" ]; then
    log_info "Enabling versioning on bucket..."
    gsutil versioning set on "gs://${BUCKET_NAME}"
fi

# Step 3: Find terraform state files
log_info "Searching for terraform state files..."
STATE_FILES=()
if [ -d "$TFSTATE_SOURCE" ]; then
    while IFS= read -r -d '' file; do
        STATE_FILES+=("$file")
    done < <(find "$TFSTATE_SOURCE" -name "*.tfstate" -print0)
else
    log_warn "Terraform state directory not found: $TFSTATE_SOURCE"
fi

if [ ${#STATE_FILES[@]} -eq 0 ]; then
    log_warn "No .tfstate files found in $TFSTATE_SOURCE"
    audit_log_entry "warning" "No terraform state files found"
    exit 0
fi

# Step 4: Backup each state file
backup_count=0
failed_count=0

for state_file in "${STATE_FILES[@]}"; do
    relative_path="${state_file#$TFSTATE_SOURCE/}"
    backup_object="${BACKUP_PREFIX}/${TIMESTAMP}/${relative_path}"
    
    log_info "Uploading: $backup_object"
    
    if gsutil -h "Cache-Control:no-cache" cp "$state_file" "gs://${BUCKET_NAME}/${backup_object}"; then
        ((backup_count++))
        log_info "✓ Uploaded successfully"
    else
        ((failed_count++))
        log_error "✗ Failed to upload: $state_file"
    fi
done

# Step 5: Set lifecycle policy (90 day hot, 365 day archive)
log_info "Applying lifecycle policy..."
cat > /tmp/lifecycle.json <<'LIFECYCLE'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 90}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 365}
      }
    ]
  }
}
LIFECYCLE

gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}" || log_warn "Could not set lifecycle policy (may already exist)"
rm /tmp/lifecycle.json

# Step 6: Verify backup integrity
log_info "Verifying backup integrity..."
verify_count=0
for state_file in "${STATE_FILES[@]}"; do
    relative_path="${state_file#$TFSTATE_SOURCE/}"
    backup_object="${BACKUP_PREFIX}/${TIMESTAMP}/${relative_path}"
    
    source_size=$(stat -f%z "$state_file" 2>/dev/null || stat -c%s "$state_file" 2>/dev/null)
    gcs_size=$(gsutil stat "gs://${BUCKET_NAME}/${backup_object}" | grep "Content-Length" | awk '{print $2}')
    
    if [ "$source_size" == "$gcs_size" ]; then
        ((verify_count++))
        log_info "✓ Integrity verified: $relative_path ($source_size bytes)"
    else
        log_error "✗ Size mismatch: $relative_path (local: $source_size, gcs: $gcs_size)"
    fi
done

# Step 7: Report status
log_info "Backup complete!"
log_info "Files uploaded: $backup_count"
log_info "Files failed: $failed_count"
log_info "Files verified: $verify_count"

# Step 8: Audit trail
if [ $failed_count -eq 0 ]; then
    audit_log_entry "success" "Backed up $backup_count terraform state files. Verified: $verify_count"
    log_info "Audit trail updated"
    exit 0
else
    audit_log_entry "failure" "Backup completed with $failed_count failures"
    log_error "Backup completed with failures"
    exit 1
fi
