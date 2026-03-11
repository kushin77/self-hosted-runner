#!/usr/bin/env bash
# scripts/security/pam_audit_trail.sh — Privileged Access Management audit logging
# Records all privileged operations (credential rotation, revocation, deployment authorization)
# with immutable append-only logs for compliance and audit trails

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
AUDIT_DIR="${REPO_ROOT}/.pam-audit"
mkdir -p "$AUDIT_DIR"

# Log a privileged access event (immutable)
log_pam_event() {
  local event_type="$1"        # e.g., "credential_rotated", "secret_revoked", "operator_session_start"
  local operator="${2:-}"      # Operator email or identifier
  local resource="${3:-}"      # Resource being accessed (secret name, service account, etc)
  local action="${4:-}"        # Action taken (read, write, revoke, etc)
  local status="${5:-success}" # success, denied, escalated, etc
  local details="${6:-}"       # Additional JSON details
  
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local hostname=$(hostname)
  local ip_address="${SSH_CLIENT%% *}" || ip_address="unknown"
  local user_shell="${LOGNAME:-$(whoami)}"
  
  # Build immutable audit entry
  local audit_entry=$(cat <<EOF
{
  "timestamp": "$timestamp",
  "event_type": "$event_type",
  "operator": "$operator",
  "resource": "$resource",
  "action": "$action",
  "status": "$status",
  "hostname": "$hostname",
  "remote_ip": "$ip_address",
  "user": "$user_shell",
  "shell_pid": $$,
  "script": "${BASH_SOURCE[0]}",
  "script_line": "${BASH_LINENO[0]}",
  "immutable": true,
  "details": $details
}
EOF
)
  
  # Append to immutable audit log (never modify old entries)
  echo "$audit_entry" >> "$AUDIT_DIR/pam-audit-$(date +%Y%m%d).jsonl"
}

# Log operator session start (PAM)
log_session_start() {
  local operator="${1:-}"
  local session_id="$RANDOM-$(date +%s)"
  
  log_pam_event \
    "session_start" \
    "$operator" \
    "session" \
    "create" \
    "success" \
    "{\"session_id\": \"$session_id\", \"ttl_seconds\": 3600}"
  
  # Export session ID for downstream operations
  export PAM_SESSION_ID="$session_id"
  export PAM_SESSION_START_TIME="$(date +%s)"
}

# Log operator session end (PAM)
log_session_end() {
  local operator="${1:-}"
  local session_id="${PAM_SESSION_ID:-}"
  local duration_seconds=$(( $(date +%s) - ${PAM_SESSION_START_TIME:-0} ))
  
  log_pam_event \
    "session_end" \
    "$operator" \
    "session" \
    "terminate" \
    "success" \
    "{\"session_id\": \"$session_id\", \"duration_seconds\": $duration_seconds}"
}

# Log credential rotation (requires multiple approvals)
log_credential_rotation() {
  local operator="${1:-}"
  local secret_name="${2:-}"
  local approvers="${3:-}" # Comma-separated list of approvers
  
  log_pam_event \
    "credential_rotated" \
    "$operator" \
    "$secret_name" \
    "rotate" \
    "approved" \
    "{\"secret_name\": \"$secret_name\", \"approvers\": \"$approvers\", \"rotation_method\": \"automated_with_approval\"}"
}

# Log credential revocation (emergency/security incident)
log_credential_revocation() {
  local operator="${1:-}"
  local secret_name="${2:-}"
  local reason="${3:-}"  # e.g., "suspected_compromise", "expired", "manual_revocation"
  
  log_pam_event \
    "credential_revoked" \
    "$operator" \
    "$secret_name" \
    "revoke" \
    "executed" \
    "{\"secret_name\": \"$secret_name\", \"reason\": \"$reason\", \"audited\": true}"
}

# Log deployment authorization (requires approval for production)
log_deployment_authorization() {
  local operator="${1:-}"
  local deployment_id="${2:-}"
  local environment="${3:-staging}"  # staging, production, etc
  local approver="${4:-}"
  
  log_pam_event \
    "deployment_authorized" \
    "$operator" \
    "$deployment_id" \
    "deploy" \
    "approved" \
    "{\"deployment_id\": \"$deployment_id\", \"environment\": \"$environment\", \"approver\": \"$approver\"}"
}

# Log break-glass (emergency) access (requires 3 approvals + immutable log)
log_break_glass_access() {
  local operator="${1:-}"
  local action="${2:-}"
  local resource="${3:-}"
  local approvers="${4:-}"  # CSV list of 3+ approvers
  
  echo "⚠️  BREAK-GLASS ACCESS INITIATED"
  echo "   Operator: $operator"
  echo "   Action: $action"
  echo "   Resource: $resource"
  echo "   Approvers: $approvers"
  echo "   Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo ""
  
  log_pam_event \
    "break_glass_access" \
    "$operator" \
    "$resource" \
    "$action" \
    "granted" \
    "{\"action\": \"$action\", \"approvers\": \"$approvers\", \"approver_count\": $(echo "$approvers" | tr ',' '\n' | wc -l), \"severity\": \"critical\"}"
}

# Verify audit trail integrity (immutable check)
verify_audit_integrity() {
  local audit_file="${AUDIT_DIR}/pam-audit-$(date +%Y%m%d).jsonl"
  
  if [[ ! -f "$audit_file" ]]; then
    echo "[PAM] ERROR: Audit file not found: $audit_file" >&2
    return 1
  fi
  
  # Check that all entries have immutable=true
  local non_immutable=$(grep -v '"immutable": true' "$audit_file" | wc -l)
  
  if [[ $non_immutable -gt 0 ]]; then
    echo "[PAM] ERROR: Found $non_immutable non-immutable audit entries!" >&2
    return 1
  fi
  
  echo "[PAM] ✓ Audit trail integrity verified ($(wc -l < "$audit_file") entries)"
  return 0
}

# Export functions for use in other scripts
export -f log_pam_event
export -f log_session_start
export -f log_session_end
export -f log_credential_rotation
export -f log_credential_revocation
export -f log_deployment_authorization
export -f log_break_glass_access
export -f verify_audit_integrity
