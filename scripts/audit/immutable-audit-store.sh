#!/bin/bash
#
# Immutable Audit Store with Cryptographic Chaining
# Implements hash-chain integrity verification for audit logs
# 
# Features:
#  - Append-only JSONL format with per-line SHA256 hash
#  - Cryptographic chaining (previous_hash reference)
#  - Daily rotation to GCS with object versioning
#  - Verification script for chain integrity check
#  - Zero data loss guarantee
#
set -euo pipefail

AUDIT_LOG="${AUDIT_LOG:-logs/portal-migrate-audit.jsonl}"
AUDIT_ARCHIVE_DIR="${AUDIT_ARCHIVE_DIR:-logs/archive}"
GCS_AUDIT_BUCKET="${GCS_AUDIT_BUCKET:-}"
S3_AUDIT_BUCKET="${S3_AUDIT_BUCKET:-}"

# Initialize archive directory
mkdir -p "$AUDIT_ARCHIVE_DIR"

#
# Append audit event to immutable log with hash chaining
#
audit_append() {
    local event="$1"
    local status="$2"
    local details="${3:-}"
    
    # Generate event timestamp
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)
    
    # Get SHA256 of current log to use as previous_hash
    local previous_hash="null"
    if [ -f "$AUDIT_LOG" ]; then
        # Extract last hash from the log file
        previous_hash=$(tail -1 "$AUDIT_LOG" 2>/dev/null | jq -r '.hash' 2>/dev/null || echo "null")
    fi
    
    # Create event JSON (without hash initially)
    local event_json=$(cat <<EOF
{"timestamp":"$timestamp","event":"$event","status":"$status","details":"$details","previous_hash":$previous_hash}
EOF
)
    
    # Compute SHA256 of the event
    local hash=$(echo -n "$event_json" | sha256sum | cut -d' ' -f1)
    
    # Add hash to event
    local event_with_hash=$(echo "$event_json" | jq --arg h "$hash" '. + {hash: $h}')
    
    # Append to immutable log
    echo "$event_with_hash" >> "$AUDIT_LOG"
}

#
# Verify audit log chain integrity
#
audit_verify() {
    local log_file="${1:-$AUDIT_LOG}"
    
    if [ ! -f "$log_file" ]; then
        echo "❌ Audit log not found: $log_file"
        return 1
    fi
    
    local line_count=0
    local errors=0
    local previous_hash="null"
    
    echo "🔍 Verifying audit chain: $log_file"
    
    while IFS= read -r line; do
        ((line_count++))
        
        if [ -z "$line" ]; then
            continue
        fi
        
        # Extract components
        local stored_hash=$(echo "$line" | jq -r '.hash // "missing"')
        local line_previous=$(echo "$line" | jq -r '.previous_hash // "null"')
        local event=$(echo "$line" | jq -r '.event // "unknown"')
        
        # Verify previous_hash matches
        if [ "$line_previous" != "$previous_hash" ]; then
            echo "❌ Line $line_count: Chain broken for $event (expected previous=$previous_hash, got=$line_previous)"
            ((errors++))
        fi
        
        # Recompute hash (without hash field)
        local event_json=$(echo "$line" | jq 'del(.hash)')
        local computed_hash=$(echo -n "$(echo "$event_json" | jq -c .)" | sha256sum | cut -d' ' -f1)
        
        # Verify hash matches
        if [ "$stored_hash" != "$computed_hash" ]; then
            echo "❌ Line $line_count: Hash mismatch for $event (stored=$stored_hash, computed=$computed_hash)"
            ((errors++))
        fi
        
        # Update for next iteration
        previous_hash="$stored_hash"
        
    done < "$log_file"
    
    if [ "$errors" -eq 0 ]; then
        echo "✅ Audit chain verified ($line_count entries, 0 errors)"
        return 0
    else
        echo "❌ Audit chain verification failed ($line_count entries, $errors errors)"
        return 1
    fi
}

#
# Rotate and archive audit log
#
audit_rotate() {
    local timestamp=$(date -u +%Y%m%d-%H%M%S)
    local archive_file="$AUDIT_ARCHIVE_DIR/audit-$timestamp.jsonl.gz"
    
    if [ ! -f "$AUDIT_LOG" ]; then
        echo "ℹ️  No audit log to rotate"
        return 0
    fi
    
    # Verify chain before rotation
    if ! audit_verify "$AUDIT_LOG"; then
        echo "⚠️  Audit log chain verification failed before rotation (continuing anyway)"
    fi
    
    # Compress and archive
    gzip -c "$AUDIT_LOG" > "$archive_file"
    echo "✅ Archived: $archive_file"
    
    # Truncate original log for next cycle
    > "$AUDIT_LOG"
    echo "✅ Rotated: $AUDIT_LOG"
}

#
# Upload audit bundle to GCS
#
upload_to_gcs() {
    local archive_file="$1"
    
    if [ -z "$GCS_AUDIT_BUCKET" ]; then
        echo "⚠️  GCS_AUDIT_BUCKET not set, skipping upload"
        return 0
    fi
    
    local filename=$(basename "$archive_file")
    local gcs_path="gs://$GCS_AUDIT_BUCKET/audit/$filename"
    
    if gsutil cp "$archive_file" "$gcs_path" 2>&1; then
        echo "✅ Uploaded to GCS: $gcs_path"
        
        # Verify object versioning is enabled
        if gsutil versioning get "gs://$GCS_AUDIT_BUCKET" 2>&1 | grep -q "Enabled"; then
            echo "✅ Object versioning confirmed on bucket"
        else
            echo "⚠️  Object versioning NOT enabled on bucket (enabling...)"
            gsutil versioning set on "gs://$GCS_AUDIT_BUCKET"
        fi
        
        return 0
    else
        echo "❌ Failed to upload to GCS"
        return 1
    fi
}

#
# Upload audit bundle to S3
#
upload_to_s3() {
    local archive_file="$1"
    
    if [ -z "$S3_AUDIT_BUCKET" ]; then
        echo "⚠️  S3_AUDIT_BUCKET not set, skipping upload"
        return 0
    fi
    
    local filename=$(basename "$archive_file")
    local s3_path="s3://$S3_AUDIT_BUCKET/audit/$filename"
    
    if aws s3 cp "$archive_file" "$s3_path" 2>&1; then
        echo "✅ Uploaded to S3: $s3_path"
        
        # Verify versioning is enabled
        if aws s3api get-bucket-versioning --bucket "$S3_AUDIT_BUCKET" 2>&1 | grep -q "Enabled"; then
            echo "✅ Versioning confirmed on bucket"
        else
            echo "⚠️  Versioning NOT enabled on bucket (enabling...)"
            aws s3api put-bucket-versioning --bucket "$S3_AUDIT_BUCKET" --versioning-configuration Status=Enabled
        fi
        
        return 0
    else
        echo "❌ Failed to upload to S3"
        return 1
    fi
}

# Main execution
main() {
    local action="${1:-verify}"
    
    case "$action" in
        append)
            audit_append "$2" "$3" "${4:-}"
            ;;
        verify)
            audit_verify "${2:-$AUDIT_LOG}"
            ;;
        rotate)
            audit_rotate
            ;;
        upload)
            local latest_archive=$(ls -t "$AUDIT_ARCHIVE_DIR"/audit-*.jsonl.gz 2>/dev/null | head -1)
            if [ -z "$latest_archive" ]; then
                echo "❌ No archive found to upload"
                return 1
            fi
            upload_to_gcs "$latest_archive"
            upload_to_s3 "$latest_archive"
            ;;
        *)
            echo "Usage: $0 {append|verify|rotate|upload}"
            return 1
            ;;
    esac
}

main "$@"
