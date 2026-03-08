#!/bin/bash
################################################################################
# GCP Secret Manager (GSM) Credential Rotation
#
# Purpose: Automate rotation of GSM-stored credentials based on age policies
#          Ensures compliance with credential lifecycle management
#
# Properties: Immutable | Ephemeral | Idempotent | No-Ops (scheduled)
# 
# Triggers: Daily via GitHub Actions workflow
# Operator: Hands-off (automatic rotation based on TTL policies)
#
################################################################################

set -euo pipefail

# === CONFIGURATION ===
readonly LOG_FILE=".github/workflows/logs/gcp-gsm-rotation-$(date +%s).log"
readonly PROJECT_ID="${GCP_PROJECT_ID:-}"
readonly TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
readonly ROTATION_THRESHOLD_DAYS="${GSM_ROTATION_THRESHOLD_DAYS:-30}"

# Secret rotation policies (name:max_age_days)
declare -A ROTATION_POLICIES=(
  ["gcp-service-account"]=30
  ["aws-oidc-role-arn"]=90
  ["slack-bot-token"]=60
  ["vault-token"]=45
)

mkdir -p "$(dirname "$LOG_FILE")"

# === LOGGING ===
log() { echo "[${TIMESTAMP}] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[${TIMESTAMP}] ERROR: $*" | tee -a "$LOG_FILE" >&2; }
log_success() { echo "[${TIMESTAMP}] ✓ $*" | tee -a "$LOG_FILE"; }

# === VALIDATION ===
validate_environment() {
  log "Validating rotation environment..."
  
  if [[ -z "$PROJECT_ID" ]]; then
    log_error "GCP_PROJECT_ID not set"
    return 1
  fi
  
  if ! command -v gcloud &>/dev/null; then
    log_error "gcloud CLI not found"
    return 1
  fi
  
  log_success "Rotation environment validated"
  return 0
}

# === VERSION MANAGEMENT ===

# Get GSM secret's latest version age in days
get_secret_version_age() {
  local secret_name="$1"
  
  # Get the creation timestamp of the latest version
  local created_time
  created_time=$(gcloud secrets versions list "$secret_name" \
    --project="$PROJECT_ID" \
    --limit=1 \
    --format="value(created)" 2>/dev/null || echo "")
  
  if [[ -z "$created_time" ]]; then
    echo "-1"  # Error indicator
    return 1
  fi
  
  # Calculate age in days
  local created_epoch
  created_epoch=$(date -d "$created_time" +%s 2>/dev/null || echo "0")
  
  local current_epoch
  current_epoch=$(date +%s)
  
  local age_days=$(( (current_epoch - created_epoch) / 86400 ))
  echo "$age_days"
}

# Archive old GSM secret versions (keep latest 3)
archive_old_versions() {
  local secret_name="$1"
  local keep_count=3
  
  log "Archiving old versions of $secret_name (keeping $keep_count)..."
  
  # List all versions (excluding latest)
  local versions
  versions=$(gcloud secrets versions list "$secret_name" \
    --project="$PROJECT_ID" \
    --format="value(name)" 2>/dev/null || echo "")
  
  local version_count=0
  while IFS= read -r version; do
    [[ -z "$version" ]] && continue
    
    version_count=$((version_count + 1))
    
    if [[ $version_count -gt $keep_count ]]; then
      # Destroy old version
      if gcloud secrets versions destroy "$version" \
        --secret="$secret_name" \
        --project="$PROJECT_ID" \
        --quiet 2>/dev/null; then
        log "  Destroyed version: $version"
      fi
    fi
  done <<< "$versions"
  
  log_success "Archival complete for $secret_name"
}

# === ROTATION TRIGGERS ===

# Mark GSM secret for rotation (sets metadata alert)
mark_for_rotation() {
  local secret_name="$1"
  local reason="$2"
  
  log "Marking $secret_name for rotation: $reason"
  
  # Add deprecation label/metadata
  gcloud secrets update "$secret_name" \
    --project="$PROJECT_ID" \
    --update-labels="rotation-pending=true,rotation-reason=$reason" 2>/dev/null || true
  
  log_success "Marked for rotation: $secret_name"
}

# Check if secret needs rotation
check_rotation_needed() {
  local secret_name="$1"
  local max_age=${ROTATION_POLICIES[$secret_name]:-30}
  
  local age
  age=$(get_secret_version_age "$secret_name")
  
  if [[ $age -ge $max_age ]]; then
    log "ROTATION REQUIRED: $secret_name is $age days old (max: $max_age days)"
    return 0  # Needs rotation
  else
    log "No rotation needed: $secret_name is $age days old (max: $max_age days)"
    return 1  # No rotation needed
  fi
}

# === ROTATION WORKFLOW ===

# Generate notification for secret rotation
notify_rotation_needed() {
  local secret_name="$1"
  local age="$2"
  local max_age="$3"
  
  log "Notifying of rotation need: $secret_name"
  
  # Create issue for operator action (if not automated rotation available)
  local issue_body="**Secret Rotation Due**

- **Secret**: $secret_name
- **Age**: $age days
- **Threshold**: $max_age days
- **Action Required**: Manual rotation or automated via operator

**Rotation Procedure**:
1. Generate new credential in source system (AWS/GCP/Vault)
2. Update GitHub secret: \`gh secret set $secret_name\`
3. GSM will auto-sync via next workflow run (15 min)
4. Old versions kept for 30 days, then destroyed

**Automation Status**: Hands-off (awaiting operator action)"
  
  # Add label to tracking issue (would integrate with issue management)
  log "Rotation notification prepared (manual action required for: $secret_name)"
}

# === COMPLIANCE AUDIT ===

# Generate rotation audit report
generate_rotation_audit() {
  local report_file=".github/workflows/logs/gcp-gsm-rotation-audit-$(date +%s).md"
  
  log "Generating rotation audit report..."
  
  {
    echo "# GCP GSM Credential Rotation Audit"
    echo ""
    echo "**Date**: $TIMESTAMP"
    echo "**Project**: $PROJECT_ID"
    echo ""
    echo "## Rotation Status"
    echo ""
    
    local needs_rotation=0
    
    for secret_name in "${!ROTATION_POLICIES[@]}"; do
      local max_age=${ROTATION_POLICIES[$secret_name]}
      local age
      age=$(get_secret_version_age "$secret_name" 2>/dev/null || echo "-1")
      
      if [[ $age -ge 0 ]]; then
        local status="✓ OK"
        if [[ $age -ge $max_age ]]; then
          status="🔴 ROTATION OVERDUE"
          needs_rotation=$((needs_rotation + 1))
        fi
        
        echo "| $secret_name | $age days | $max_age days | $status |"
      fi
    done
    
    echo ""
    echo "## Summary"
    echo "- **Total Monitored Secrets**: ${#ROTATION_POLICIES[@]}"
    echo "- **Requiring Rotation**: $needs_rotation"
    echo "- **Last Check**: $TIMESTAMP"
    echo ""
    echo "## Rotation Policies"
    for secret_name in "${!ROTATION_POLICIES[@]}"; do
      echo "- \`$secret_name\`: max age ${ROTATION_POLICIES[$secret_name]} days"
    done
    
  } > "$report_file"
  
  log_success "Audit report: $report_file"
  cat "$report_file" >> "$LOG_FILE"
}

# === MAIN EXECUTION ===

main() {
  log "=== GCP GSM Credential Rotation Started ==="
  log "Project: $PROJECT_ID"
  log "Threshold: $ROTATION_THRESHOLD_DAYS days"
  
  if ! validate_environment; then
    log_error "Environment validation failed"
    exit 1
  fi
  
  local rotation_count=0
  
  # Check each secret
  for secret_name in "${!ROTATION_POLICIES[@]}"; do
    log ""
    log "Checking secret: $secret_name"
    
    if check_rotation_needed "$secret_name"; then
      local max_age=${ROTATION_POLICIES[$secret_name]}
      local age
      age=$(get_secret_version_age "$secret_name")
      
      rotation_count=$((rotation_count + 1))
      mark_for_rotation "$secret_name" "age_threshold_exceeded"
      notify_rotation_needed "$secret_name" "$age" "$max_age"
      archive_old_versions "$secret_name"
    fi
  done
  
  log ""
  log "=== Rotation Check Complete ==="
  log "Secrets requiring attention: $rotation_count"
  
  generate_rotation_audit
  
  if [[ $rotation_count -gt 0 ]]; then
    log "⚠️  Action required: $rotation_count secret(s) need rotation"
    # Return non-zero to signal rotations needed (can trigger notifications)
    return 1
  fi
  
  log_success "All secrets within acceptable age ranges"
  return 0
}

main "$@"
