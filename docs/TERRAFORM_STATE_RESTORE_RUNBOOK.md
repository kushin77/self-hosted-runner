# Terraform State Restore Runbook

**Document**: Terraform State Disaster Recovery
**Updated**: 2026-03-10
**Scope**: Self-Hosted Runner Infrastructure
**Automation**: Backups created every 6 hours via Cloud Scheduler

## Overview

This runbook provides step-by-step procedures to restore Terraform state from GCS backups in case of:
- State file corruption
- Accidental state deletion
- Terraform lock timeout requiring full reset
- Infrastructure recovery after cluster failure

## Prerequisites

### Required Tools
- `gcloud` CLI (latest version)
- `gsutil` (included with gcloud)
- `terraform` (v1.0+)
- Proper IAM permissions:
  - `storage.buckets.get`
  - `storage.objects.get`
  - `storage.objects.list`

### Required Access
- GCP Project ID configured in `$GOOGLE_CLOUD_PROJECT`
- Service account key with terraform state access
- SSH access to terraform runner host

### Verification
```bash
gcloud auth list
gcloud config get-value project
gsutil ls gs://nexusshield-terraform-backups/
```

## Backup Location & Structure

**Bucket**: `gs://nexusshield-terraform-backups/`
**Naming**: `terraform-state-YYYY-MM-DD-HHMMSS.json`
**Versioning**: Enabled (recovery up to 90 days hot + 365 days archived)
**Lifecycle**: 90 days standard storage → 365 days nearline (cost optimized)

## Restore Procedures

### Procedure 1: List Available Backups

```bash
# List all recent backups
gsutil ls -h gs://nexusshield-terraform-backups/ | head -20

# List backups from specific date
gsutil ls gs://nexusshield-terraform-backups/ | grep "2026-03-10"

# Show backup size and timestamp
gsutil ls -L gs://nexusshield-terraform-backups/terraform-state-*.json | head -10
```

### Procedure 2: Quick Restore (Last Good Backup)

**Use Case**: Restore from most recent backup
**Time**: ~2 minutes
**Risk**: Low (confirmed working state)

```bash
#!/bin/bash
set -euo pipefail

# Configuration
GCS_BUCKET="cs://nexusshield-terraform-backups"
TERRAFORM_DIR="${HOME}/infrastructure/terraform"
BACKUP_DIR="${TERRAFORM_DIR}/.backup-$(date +%s)"

# Step 1: Create backup of current state (even if corrupted)
mkdir -p "${BACKUP_DIR}"
if [[ -f "${TERRAFORM_DIR}/terraform.tfstate" ]]; then
    cp "${TERRAFORM_DIR}/terraform.tfstate" "${BACKUP_DIR}/"
    echo "✅ Backed up current state to ${BACKUP_DIR}"
else
    echo "⚠️  No current state file found"
fi

# Step 2: Find latest backup
LATEST_BACKUP=$(gsutil ls "${GCS_BUCKET}/terraform-state-"*.json | tail -1)
echo "📥 Restoring from: ${LATEST_BACKUP}"

# Step 3: Download latest backup
gsutil cp "${LATEST_BACKUP}" "${TERRAFORM_DIR}/terraform.tfstate.new"
echo "✅ Downloaded backup"

# Step 4: Verify backup integrity
if ! jq empty "${TERRAFORM_DIR}/terraform.tfstate.new" 2>/dev/null; then
    echo "❌ Backup file is corrupt JSON"
    exit 1
fi
echo "✅ Backup file is valid JSON"

# Step 5: Replace state file
mv "${TERRAFORM_DIR}/terraform.tfstate.new" "${TERRAFORM_DIR}/terraform.tfstate"
echo "✅ State file replaced"

# Step 6: Record in audit log
cat >> "${TERRAFORM_DIR}/.terraform-restore-audit.jsonl" <<EOF
{"timestamp": "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")", "event": "state_restore", "backup_source": "${LATEST_BACKUP}", "status": "success"}
EOF

echo "✅ Restore complete - state file recovered"
echo "⚠️  Next: Run 'terraform refresh' to sync state with infrastructure"
```

### Procedure 3: Restore from Specific Date

**Use Case**: Revert to known-good state from specific date
**Time**: ~3 minutes
**Risk**: Medium (may include planned infrastructure changes)

```bash
#!/bin/bash
set -euo pipefail

# Configuration
TARGET_DATE="${1:-2026-03-10}"  # YYYY-MM-DD format
GCS_BUCKET="gs://nexusshield-terraform-backups"
TERRAFORM_DIR="${HOME}/infrastructure/terraform"

# Find backup from target date
BACKUP=$(gsutil ls "${GCS_BUCKET}/" | grep "terraform-state-${TARGET_DATE}" | tail -1)

if [[ -z "${BACKUP}" ]]; then
    echo "❌ No backup found for date: ${TARGET_DATE}"
    gsutil ls "${GCS_BUCKET}/" | grep "terraform-state-" | tail -5
    exit 1
fi

echo "📥 Found backup: ${BACKUP}"

# Create backup directory
BACKUP_DIR="${TERRAFORM_DIR}/.backup-$(date +%s)"
mkdir -p "${BACKUP_DIR}"
cp "${TERRAFORM_DIR}/terraform.tfstate" "${BACKUP_DIR}/"

# Download and verify
gsutil cp "${BACKUP}" "${TERRAFORM_DIR}/terraform.tfstate.new"
jq empty "${TERRAFORM_DIR}/terraform.tfstate.new" || {
    echo "❌ Backup JSON is invalid"
    exit 1
}

# Restore
mv "${TERRAFORM_DIR}/terraform.tfstate.new" "${TERRAFORM_DIR}/terraform.tfstate"

echo "✅ Restored state from ${TARGET_DATE}"
echo "⚠️  Review changes: terraform plan"
```

### Procedure 4: Selective State Item Restore

**Use Case**: Restore only specific resources (e.g., single database)
**Time**: ~5 minutes
**Risk**: Medium (must understand state dependencies)

```bash
#!/bin/bash
set -euo pipefail

RESOURCE_ADDRESS="${1}"  # Example: "aws_db_instance.main"
GCS_BUCKET="gs://nexusshield-terraform-backups"
TERRAFORM_DIR="${HOME}/infrastructure/terraform"

# Get latest backup
LATEST=$(gsutil ls "${GCS_BUCKET}/terraform-state-"*.json | tail -1)

# Extract just this resource from backup
gsutil cp "${LATEST}" /tmp/backup-full.json

# Extract single resource (using jq)
RESOURCE_STATE=$(jq --arg addr "${RESOURCE_ADDRESS}" \
    '.resources[] | select(.address == $addr)' \
    /tmp/backup-full.json)

echo "Resource state to restore:"
echo "${RESOURCE_STATE}" | jq .

# Manually import or apply (choose based on your TF version)
echo "⚠️  Manually apply resource with terraform import or apply"
```

### Procedure 5: Full State File Reset (Emergency)

**Use Case**: Complete infrastructure recovery
**Time**: ~10 minutes
**Risk**: High (deletes all IaC tracking)
**When**: Only if state file is completely unrecoverable

```bash
#!/bin/bash
set -euo pipefail

TERRAFORM_DIR="${HOME}/infrastructure/terraform"

echo "⚠️  WARNING: This will reset ALL terraform state"
echo "⚠️  You will lose tracking of all managed infrastructure"
echo "⚠️  Re-importing 30+ resources is time-intensive"
read -p "Type 'RESET_STATE_CONFIRM' to continue: " CONFIRM

if [[ "${CONFIRM}" != "RESET_STATE_CONFIRM" ]]; then
    echo "Cancelled"
    exit 0
fi

# Create emergency backup
BACKUP_DIR="${TERRAFORM_DIR}/.emergency-backup-$(date +%s)"
mkdir -p "${BACKUP_DIR}"
cp "${TERRAFORM_DIR}/terraform.tfstate" "${BACKUP_DIR}/"
cp "${TERRAFORM_DIR}/terraform.tfstate.backup" "${BACKUP_DIR}/" 2>/dev/null || true

# Remove state file
rm "${TERRAFORM_DIR}/terraform.tfstate"
rm "${TERRAFORM_DIR}/terraform.tfstate.backup" 2>/dev/null || true

# Reinitialize
cd "${TERRAFORM_DIR}"
terraform init -reconfigure

echo "✅ State file reset complete"
echo "⚠️  Next: terraform import to re-add managed resources"
echo "📂 Old state backed up to: ${BACKUP_DIR}"
```

## Verify After Restore

### Immediate Checks

```bash
# 1. Verify state file is valid JSON
jq . "${TERRAFORM_DIR}/terraform.tfstate}" > /dev/null && echo "✅ Valid JSON"

# 2. Check resource count
RESOURCE_COUNT=$(jq '.resources | length' "${TERRAFORM_DIR}/terraform.tfstate")
echo "📊 Resources in state: ${RESOURCE_COUNT}"

# 3. Preview what terraform will do
cd "${TERRAFORM_DIR}"
terraform plan -no-color > /tmp/plan.txt
PLAN_CHANGES=$(grep -c "No changes" /tmp/plan.txt || grep -c "will be" /tmp/plan.txt || echo "0")
echo "📋 Proposed changes: ${PLAN_CHANGES}"

# 4. Show drift from current infrastructure
terraform refresh -lock=false
terraform plan -detailed-exitcode > /dev/null || true
```

### Validation Checklist

- [ ] State file is valid JSON
- [ ] terraform.tfstate file size is reasonable (>100KB)
- [ ] terraform plan shows expected state
- [ ] Number of resources matches expectations
- [ ] No auto-import errors in terraform logs
- [ ] All critical resources present in state
- [ ] No orphaned resources in infrastructure
- [ ] Documentation updated with restore date

## Backup Verification

### Monthly Backup Test

```bash
#!/bin/bash
# Run monthly to ensure backups are restorable

GCS_BUCKET="gs://nexusshield-terraform-backups"
TEST_DIR="/tmp/terraform-backup-test-$(date +%s)"

mkdir -p "${TEST_DIR}"
cd "${TEST_DIR}"

# Get a random backup from last 30 days
BACKUP=$(gsutil ls "${GCS_BUCKET}/" | grep "terraform-state-" | tail -5 | head -1)

echo "Testing backup: ${BACKUP}"

# Download
gsutil cp "${BACKUP}" ./terraform.tfstate.test

# Validate
if jq empty ./terraform.tfstate.test 2>/dev/null; then
    echo "✅ Backup is valid JSON"
    LINES=$(wc -l < ./terraform.tfstate.test)
    echo "✅ Backup has ${LINES} lines"
    
    # Check key sections exist
    if jq '.terraform_version' ./terraform.tfstate.test >/dev/null; then
        echo "✅ Contains terraform_version"
    fi
    if jq '.resources | length' ./terraform.tfstate.test >/dev/null; then
        RESOURCE_COUNT=$(jq '.resources | length' ./terraform.tfstate.test)
        echo "✅ Contains ${RESOURCE_COUNT} resources"
    fi
else
    echo "❌ Backup JSON is INVALID"
    exit 1
fi

# Cleanup
cd /
rm -rf "${TEST_DIR}"

echo "✅ Backup verification complete"
```

## Troubleshooting

### Error: "State file is locked"
```bash
# Force unlock (DANGEROUS - use only if no terraform is running)
terraform force-unlock <LOCK_ID>

# Or restore from backup and force-unlock if needed
```

### Error: "Unable to calculate checksums"
- State file may be corrupt
- Restore from backup
- If all backups fail, perform full reset

### Error: "Module/resource not found"
- State references deleted resource
- Restore from earlier backup before deletion
- Or manually remove from state: `terraform state rm <address>`

### Slow terraform operations after restore
```bash
# Refresh and optimize
terraform refresh
terraform state list | wc -l  # Confirm resource count
terraform validate            # Check state validity
```

## Prevention & Best Practices

1. **Enable GCS versioning**: Already configured
2. **Test restores** monthly using backup verification script
3. **Monitor backup creation**: Check Cloud Scheduler jobs
4. **Keep local backup**: `.backup-*` directories created during restore
5. **Document changes**: Update this runbook after any infrastructure changes
6. **Alert on failures**: Cloud Monitoring notifies on backup job failures
7. **Access control**: Restrict IAM permissions to minimum needed

## Emergency Contact

If restore procedures fail:
1. Check Cloud Logging
2. Verify GCS bucket permissions
3. Preserve current state file (even if corrupted)
4. Contact Infrastructure team with:
   - Error messages
   - Timestamp of state file corruption
   - Last known good backup date
   - Current error logs from `terraform` and `gcloud`

---

**Last Updated**: 2026-03-10
**Backup Schedule**: Every 6 hours (automated)
**Backup Retention**: 90 days hot + 365 days nearline archive
**Recovery Time Objective (RTO)**: < 15 minutes
**Recovery Point Objective (RPO)**: 6 hours
