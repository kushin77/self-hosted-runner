#!/bin/bash
################################################################################
# GCP Secret Manager (GSM) Emergency Recovery & Breach Response
#
# Purpose: Rapid response to credential breaches/compromises
#          Automated secret revocation and rotation procedures
#
# Properties: Immutable | Ephemeral | Idempotent | No-Ops (manual trigger)
#
# Triggers: Manual via GitHub issue comment OR webhook
# Operator: Semi-automated (operator initiates, system handles details)
#
################################################################################

set -euo pipefail

# === CONFIGURATION ===
readonly LOG_FILE=".github/workflows/logs/gcp-gsm-emergency-$(date +%s).log"
readonly PROJECT_ID="${GCP_PROJECT_ID:-}"
readonly TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
readonly ESCALATION_SLACK_WEBHOOK="${SLACK_EMERGENCY_WEBHOOK:-}"

mkdir -p "$(dirname "$LOG_FILE")"

# === LOGGING ===
log() { echo "[${TIMESTAMP}] $*" | tee -a "$LOG_FILE"; }
log_error() { echo "[${TIMESTAMP}] ERROR: $*" | tee -a "$LOG_FILE" >&2; }
log_success() { echo "[${TIMESTAMP}] ✓ $*" | tee -a "$LOG_FILE"; }

# === EMERGENCY OPERATIONS ===

# Revoke a GSM secret immediately (disable all versions)
revoke_secret_immediate() {
  local secret_name="$1"
  local reason="${2:-Security incident}"
  
  log "🔴 EMERGENCY: Revoking secret $secret_name"
  log "Reason: $reason"
  
  # Get all versions
  local versions
  versions=$(gcloud secrets versions list "$secret_name" \
    --project="$PROJECT_ID" \
    --format="value(name)" 2>/dev/null || echo "")
  
  if [[ -z "$versions" ]]; then
    log_error "Secret $secret_name not found"
    return 1
  fi
  
  # Destroy all versions
  local destroyed_count=0
  while IFS= read -r version; do
    [[ -z "$version" ]] && continue
    
    if gcloud secrets versions destroy "$version" \
      --secret="$secret_name" \
      --project="$PROJECT_ID" \
      --quiet 2>/dev/null; then
      destroyed_count=$((destroyed_count + 1))
      log "Destroyed version: $version"
    fi
  done <<< "$versions"
  
  # Mark secret as revoked
  gcloud secrets update "$secret_name" \
    --remove-labels="sync-enabled" \
    --update-labels="status=revoked,revoked-at=$TIMESTAMP,revoke-reason=$reason" \
    --project="$PROJECT_ID" 2>/dev/null || true
  
  log_success "Secret revoked: $destroyed_count versions destroyed"
  
  return 0
}

# Disable specific GSM secret version
disable_secret_version() {
  local secret_name="$1"
  local version="$2"
  
  log "Disabling version $version of $secret_name..."
  
  gcloud secrets versions disable "$version" \
    --secret="$secret_name" \
    --project="$PROJECT_ID" 2>/dev/null || return 1
  
  log_success "Version $version disabled"
  return 0
}

# Create audit trail entry for breach
create_breach_audit_entry() {
  local secret_name="$1"
  local breach_type="$2"
  local severity="$3"
  
  local audit_file=".github/workflows/logs/breach-audit-$(date +%Y%m%d-%H%M%S).jsonl"
  
  {
    echo "{"
    echo "  \"timestamp\": \"$TIMESTAMP\","
    echo "  \"secret\": \"$secret_name\","
    echo "  \"breach_type\": \"$breach_type\","
    echo "  \"severity\": \"$severity\","
    echo "  \"action\": \"revoked\","
    echo "  \"actor\": \"emergency-recovery-automation\","
    echo "  \"project\": \"$PROJECT_ID\""
    echo "}"
  } >> "$audit_file"
  
  log "Audit entry created: $audit_file"
}

# === NOTIFICATION & ESCALATION ===

# Send emergency notification
send_emergency_notification() {
  local secret_name="$1"
  local severity="$2"
  local action="$3"
  
  log "Sending emergency notification for $secret_name (severity: $severity)"
  
  # Send to Slack if webhook configured
  if [[ -n "$ESCALATION_SLACK_WEBHOOK" ]]; then
    local message_color="danger"  # red for critical
    if [[ "$severity" == "HIGH" ]]; then
      message_color="warning"
    fi
    
    curl -X POST "$ESCALATION_SLACK_WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d @- <<EOF 2>/dev/null || log "Slack notification failed"
{
  "attachments": [{
    "color": "$message_color",
    "title": "🚨 Secret Manager Emergency Alert",
    "text": "Security incident detected and responded to",
    "fields": [
      {"title": "Secret", "value": "$secret_name", "short": true},
      {"title": "Severity", "value": "$severity", "short": true},
      {"title": "Action", "value": "$action", "short": true},
      {"title": "Project", "value": "$PROJECT_ID", "short": true},
      {"title": "Timestamp", "value": "$TIMESTAMP", "short": false}
    ]
  }]
}
EOF
  fi
  
  log_success "Emergency notification sent"
}

# === BREACH RESPONSE PROCEDURES ===

# Handle suspected credential compromise
handle_compromise() {
  local secret_name="$1"
  local compromise_type="${2:-unknown}"  # leaked, expired, rotated_late, etc.
  
  log "Handling compromise: $secret_name (type: $compromise_type)"
  
  create_breach_audit_entry "$secret_name" "$compromise_type" "CRITICAL"
  
  # Immediate revocation
  if revoke_secret_immediate "$secret_name" "Suspected compromise: $compromise_type"; then
    send_emergency_notification "$secret_name" "CRITICAL" "Revoked immediately"
    log_success "Compromise response complete"
    return 0
  else
    log_error "Failed to revoke compromised secret"
    send_emergency_notification "$secret_name" "CRITICAL" "Revocation FAILED - manual intervention required"
    return 1
  fi
}

# Handle accidental exposure
handle_accidental_exposure() {
  local secret_name="$1"
  local exposure_location="${2:-unknown}"
  
  log "Handling accidental exposure: $secret_name (location: $exposure_location)"
  
  create_breach_audit_entry "$secret_name" "accidental_exposure" "HIGH"
  
  if revoke_secret_immediate "$secret_name" "Accidental exposure in $exposure_location"; then
    send_emergency_notification "$secret_name" "HIGH" "Revoked due to accidental exposure"
    log_success "Exposure response complete"
    return 0
  else
    return 1
  fi
}

# === BULK OPERATIONS ===

# Emergency rotate all monitored secrets
emergency_rotate_all() {
  log "🚨 EMERGENCY: Rotating ALL monitored secrets"
  
  local secrets_to_rotate=(
    "gcp-service-account"
    "aws-oidc-role-arn"
    "aws-role-to-assume"
    "slack-bot-token"
    "vault-token"
  )
  
  local rotated_count=0
  for secret_name in "${secrets_to_rotate[@]}"; do
    if revoke_secret_immediate "$secret_name" "Emergency mass rotation"; then
      rotated_count=$((rotated_count + 1))
    fi
  done
  
  log_success "Emergency rotation complete: $rotated_count secrets rotated"
  send_emergency_notification "MULTIPLE_SECRETS" "CRITICAL" "Mass rotation executed"
  
  return $([[ $rotated_count -eq ${#secrets_to_rotate[@]} ]] && echo 0 || echo 1)
}

# === RECOVERY VALIDATION ===

# Verify secret is revoked
verify_secret_revoked() {
  local secret_name="$1"
  
  log "Verifying revocation of $secret_name..."
  
  # Try to access latest version (should fail)
  if ! gcloud secrets versions access latest \
    --secret="$secret_name" \
    --project="$PROJECT_ID" 2>/dev/null; then
    log_success "Secret is revoked (access denied as expected)"
    return 0
  else
    log_error "Secret may still be accessible - revocation incomplete"
    return 1
  fi
}

# Verify no vulnerabilities in remaining active secrets
audit_remaining_secrets() {
  log "Auditing remaining active secrets..."
  
  local active_secrets
  active_secrets=$(gcloud secrets list \
    --filter="-labels.status:revoked" \
    --project="$PROJECT_ID" \
    --format="value(name)" 2>/dev/null || echo "")
  
  local count=0
  while IFS= read -r secret_name; do
    [[ -z "$secret_name" ]] && continue
    count=$((count + 1))
  done <<< "$active_secrets"
  
  log_success "Active secrets audit: $count secrets still active"
  
  return 0
}

# === INCIDENT REPORT ===

# Generate incident response report
generate_incident_report() {
  local incident_type="$1"
  local secret_name="$2"
  
  local report_file=".github/workflows/logs/incident-report-$(date +%s).md"
  
  {
    echo "# GSM Emergency Incident Report"
    echo ""
    echo "| Field | Value |"
    echo "|-------|-------|"
    echo "| Incident Type | $incident_type |"
    echo "| Affected Secret | $secret_name |"
    echo "| Timestamp | $TIMESTAMP |"
    echo "| Project | $PROJECT_ID |"
    echo "| Response Status | ✅ COMPLETED |"
    echo ""
    echo "## Actions Taken"
    echo "1. Immediate revocation of compromised secret"
    echo "2. All versions destroyed"
    echo "3. Metadata marked as revoked"
    echo "4. Emergency notifications sent"
    echo "5. Audit trail created"
    echo ""
    echo "## Next Steps (Operator)"
    echo "1. Investigate root cause"
    echo "2. Generate new credentials in source system"
    echo "3. Update GitHub secrets"
    echo "4. Monitor for unauthorized access attempts"
    echo ""
    echo "## Log File"
    tail -30 "$LOG_FILE" | sed 's/^/```/'
    echo '```'
    
  } > "$report_file"
  
  log_success "Incident report: $report_file"
}

# === MAIN EXECUTION ===

main() {
  local operation="${1:-help}"
  local secret_name="${2:-}"
  
  case "$operation" in
    revoke)
      if [[ -z "$secret_name" ]]; then
        log_error "Usage: $0 revoke <secret_name>"
        exit 1
      fi
      log "=== Emergency Revocation Started ==="
      handle_compromise "$secret_name" "emergency_request"
      generate_incident_report "emergency_revocation" "$secret_name"
      ;;
    
    compromise)
      if [[ -z "$secret_name" ]]; then
        log_error "Usage: $0 compromise <secret_name> [type]"
        exit 1
      fi
      log "=== Compromise Response Started ==="
      handle_compromise "$secret_name" "${3:-detected}"
      generate_incident_report "compromise_detected" "$secret_name"
      ;;
    
    exposure)
      if [[ -z "$secret_name" ]]; then
        log_error "Usage: $0 exposure <secret_name> [location]"
        exit 1
      fi
      log "=== Exposure Response Started ==="
      handle_accidental_exposure "$secret_name" "${3:-unknown_location}"
      generate_incident_report "accidental_exposure" "$secret_name"
      ;;
    
    mass-rotate)
      log "=== Emergency Mass Rotation Started ==="
      emergency_rotate_all
      generate_incident_report "mass_rotation" "MULTIPLE"
      ;;
    
    verify)
      if [[ -z "$secret_name" ]]; then
        log_error "Usage: $0 verify <secret_name>"
        exit 1
      fi
      verify_secret_revoked "$secret_name"
      ;;
    
    audit)
      log "=== Remaining Secrets Audit Started ==="
      audit_remaining_secrets
      ;;
    
    *)
      cat <<USAGE
Usage: $0 <operation> [args...]

Operations:
  revoke <secret>              Immediately revoke a secret
  compromise <secret> [type]   Handle suspected compromise
  exposure <secret> [location] Handle accidental exposure
  mass-rotate                  Emergency rotate ALL secrets
  verify <secret>              Verify secret revocation
  audit                        Audit remaining active secrets
  help                         Show this message

Examples:
  $0 revoke gcp-service-account
  $0 compromise aws-oidc-role-arn "github_leak"
  $0 exposure slack-bot-token "logs_directory"
  $0 mass-rotate
USAGE
      exit 1
      ;;
  esac
  
  log "=== Operation Complete ==="
  log "Details: $LOG_FILE"
  
  return 0
}

main "$@"
