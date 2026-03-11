#!/bin/bash
#
# Audit Log Rotation, Verification & Upload Automation
# Runs daily via systemd timer at midnight UTC
# 
# Steps:
#  1. Verify current audit log chain integrity
#  2. Rotate to gzipped archive
#  3. Upload to GCS/S3 (immutable versioned buckets)
#  4. Maintain local retention policy
#
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/home/akushnir/self-hosted-runner}"
AUDIT_SCRIPT="$REPO_ROOT/scripts/audit/immutable-audit-store.sh"
AUDIT_LOG="$REPO_ROOT/logs/portal-migrate-audit.jsonl"
AUDIT_ARCHIVE_DIR="$REPO_ROOT/logs/archive"
ROTATION_LOG="$REPO_ROOT/logs/audit-rotation.jsonl"

# Ensure script exists
if [ ! -f "$AUDIT_SCRIPT" ]; then
    echo "❌ Audit script not found: $AUDIT_SCRIPT"
    exit 1
fi

#
# Log rotation event to immutable audit trail
#
log_rotation_event() {
    local event="$1"
    local status="$2"
    local details="${3:-}"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    
    cat >> "$ROTATION_LOG" <<EOF
{"timestamp":"$timestamp","event":"$event","status":"$status","details":"$details"}
EOF
}

#
# Main rotation flow
#
main() {
    echo "═══════════════════════════════════════════════════════════"
    echo "Audit Log Rotation & Upload Automation"
    echo "Schedule: Daily at UTC midnight via systemd timer"
    echo "═══════════════════════════════════════════════════════════"
    
    mkdir -p "$AUDIT_ARCHIVE_DIR" "$(dirname "$ROTATION_LOG")"
    
    # Step 1: Verify chain integrity
    echo ""
    echo "Step 1: Verifying audit chain integrity..."
    log_rotation_event "ROTATION_START" "in-progress" "Daily rotation cycle initiated"
    
    if [ -f "$AUDIT_LOG" ]; then
        if bash "$AUDIT_SCRIPT" verify "$AUDIT_LOG" 2>&1; then
            echo "✅ Chain verification passed"
            log_rotation_event "CHAIN_VERIFY" "success" "Audit chain integrity confirmed"
        else
            echo "⚠️  Chain verification warning (continuing anyway)"
            log_rotation_event "CHAIN_VERIFY" "warning" "Chain verification detected inconsistencies"
        fi
    fi
    
    # Step 2: Rotate to archive
    echo ""
    echo "Step 2: Rotating audit log to archive..."
    if bash "$AUDIT_SCRIPT" rotate 2>&1; then
        echo "✅ Rotation successful"
        log_rotation_event "ROTATION_EXECUTE" "success" "Audit log rotated and archived"
    else
        echo "❌ Rotation failed"
        log_rotation_event "ROTATION_EXECUTE" "failure" "Failed to rotate audit log"
        exit 1
    fi
    
    # Step 3: Upload to cloud storage
    echo ""
    echo "Step 3: Uploading archive to cloud storage..."
    if bash "$AUDIT_SCRIPT" upload 2>&1; then
        echo "✅ Upload completed"
        log_rotation_event "ARCHIVE_UPLOAD" "success" "Archive uploaded to cloud storage"
    else
        echo "⚠️  Upload warning (local archive preserved)"
        log_rotation_event "ARCHIVE_UPLOAD" "warning" "Cloud upload encountered issues; local archive preserved"
    fi
    
    # Step 4: Cleanup old archives (retention: 90 days)
    echo ""
    echo "Step 4: Applying retention policy (90 days)..."
    local old_files=$(find "$AUDIT_ARCHIVE_DIR" -name "audit-*.jsonl.gz" -mtime +90 2>/dev/null | wc -l)
    if [ "$old_files" -gt 0 ]; then
        find "$AUDIT_ARCHIVE_DIR" -name "audit-*.jsonl.gz" -mtime +90 -delete
        echo "✅ Deleted $old_files old archives (>90 days)"
        log_rotation_event "RETENTION_CLEANUP" "success" "Deleted $old_files expired archives"
    else
        echo "✅ No archives older than 90 days"
        log_rotation_event "RETENTION_CLEANUP" "success" "Retention policy applied; 0 files deleted"
    fi
    
    # Summary
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "✅ Audit Rotation Complete"
    echo "═══════════════════════════════════════════════════════════"
    echo "Local archives: $(find "$AUDIT_ARCHIVE_DIR" -name "*.jsonl.gz" 2>/dev/null | wc -l)"
    echo "Rotation log: $ROTATION_LOG"
    echo ""
    
    log_rotation_event "ROTATION_COMPLETE" "success" "Daily rotation cycle finished"
}

main "$@"
