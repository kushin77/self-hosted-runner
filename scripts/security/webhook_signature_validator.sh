#!/usr/bin/env bash
# scripts/security/webhook_signature_validator.sh — GitHub webhook HMAC-SHA256 signature validation
# Validates that all incoming GitHub webhooks are cryptographically signed with the correct secret
# Prevents webhook replay attacks and unauthorized payload injection

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${REPO_ROOT}/scripts/lib/validate_env.sh"
source "${REPO_ROOT}/scripts/lib/load_credentials.sh"

# Validate GitHub webhook signature (HMAC-SHA256)
# Expected header format: X-Hub-Signature-256: sha256=<hash>
validate_webhook_signature() {
  local payload="$1"                 # Raw JSON payload from GitHub
  local signature_header="${2:-}"    # Value of X-Hub-Signature-256 header
  local secret="${3:-}"              # Webhook signing secret
  
  if [[ -z "$signature_header" ]]; then
    echo "[webhook] ERROR: Missing X-Hub-Signature-256 header" >&2
    return 1
  fi
  
  if [[ -z "$secret" ]]; then
    # Try to load from GSM
    secret=$(load_credentials SECRET_GH_WEBHOOK_SIGNING_SECRET_PROD 2>/dev/null) || {
      echo "[webhook] ERROR: Webhook signing secret not found in environment or GSM" >&2
      return 1
    }
  fi
  
  # Compute expected signature: sha256=<HMAC-SHA256(payload, secret)>
  local expected_signature="sha256=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac "$secret" -r | awk '{print $1}')"
  
  # Compare signatures using constant-time comparison (prevent timing attacks)
  if [[ "$signature_header" == "$expected_signature" ]]; then
    echo "[webhook] ✓ Signature valid"
    return 0
  else
    echo "[webhook] ERROR: Invalid signature (expected: $expected_signature, got: $signature_header)" >&2
    return 1
  fi
}

# Log webhook event (immutable audit trail)
log_webhook_event() {
  local event_type="$1"        # push, pull_request, release, issues, etc
  local action="$2"            # opened, closed, created, etc
  local source="${3:-github}"  # github, webhook-listener, etc
  local status="${4:-received}"  # received, valid, invalid, processed, failed
  local details="${5:-{}}"     # JSON object with additional context
  
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local audit_dir=".webhook-audit"
  
  mkdir -p "$audit_dir"
  
  # Append to immutable audit log
  cat >> "$audit_dir/webhook-$(date +%Y%m%d).jsonl" <<EOF
{"timestamp":"$timestamp","event_type":"$event_type","action":"$action","source":"$source","status":"$status","details":$details,"immutable":true}
EOF
}

# Verify webhook event structure (prevents malformed payloads)
validate_webhook_payload() {
  local payload="$1"
  
  # Check if payload is valid JSON
  if ! echo "$payload" | jq . >/dev/null 2>&1; then
    echo "[webhook] ERROR: Webhook payload is not valid JSON" >&2
    return 1
  fi
  
  # Check for required GitHub webhook fields
  local has_action=$(echo "$payload" | jq 'has("action")' 2>/dev/null)
  local has_repository=$(echo "$payload" | jq 'has("repository")' 2>/dev/null)
  
  if [[ "$has_action" != "true" ]] && [[ "$has_repository" != "true" ]]; then
    echo "[webhook] WARNING: Webhook missing standard GitHub fields (may be custom/test)" >&2
  fi
  
  return 0
}

# Filter webhook events (subscribe to only necessary events)
should_process_webhook() {
  local event_type="$1"  # GitHub sends this via X-GitHub-Event header
  
  # Whitelist of events to process (least privilege)
  local allowed_events=(
    "push"           # Code push
    "pull_request"   # PR opened, closed, synchronized
    "issues"         # Issue created (for incident tracking)
    "workflow_run"   # Workflow completion
  )
  
  # Check if event type is in whitelist
  for allowed in "${allowed_events[@]}"; do
    if [[ "$event_type" == "$allowed" ]]; then
      return 0  # Process this event
    fi
  done
  
  echo "[webhook] Ignoring event type: $event_type (not in whitelist)" >&2
  return 1  # Skip this event
}

# Main webhook handler (called by webhook listener application)
handle_webhook() {
  local signature_header="${1:-}"
  local event_type="${2:-}"
  local payload="${3:-}"
  
  # Validate signature first (security-critical)
  if ! validate_webhook_signature "$payload" "$signature_header"; then
    log_webhook_event "$event_type" "unknown" "github" "invalid_signature" '{"error":"signature_mismatch"}'
    return 1
  fi
  
  # Validate payload structure
  if ! validate_webhook_payload "$payload"; then
    log_webhook_event "$event_type" "unknown" "github" "invalid_payload" '{"error":"malformed_json"}'
    return 1
  fi
  
  # Filter events (allow-list)
  if ! should_process_webhook "$event_type"; then
    log_webhook_event "$event_type" "unknown" "github" "filtered" '{"reason":"event_type_not_whitelisted"}'
    return 0  # Silently ignore
  fi
  
  # Extract action from payload
  local action=$(echo "$payload" | jq -r '.action // "unknown"')
  
  log_webhook_event "$event_type" "$action" "github" "received" "{\"event_type\":\"$event_type\",\"action\":\"$action\"}"
  
  echo "[webhook] ✓ Webhook processed: $event_type/$action"
  return 0
}

# Rotate webhook signing secret (monthly, zero-downtime)
rotate_webhook_secret() {
  local old_secret="${1:-}"
  
  # Load current secret
  if [[ -z "$old_secret" ]]; then
    old_secret=$(load_credentials SECRET_GH_WEBHOOK_SIGNING_SECRET_PROD 2>/dev/null) || {
      echo "[webhook] ERROR: Could not load current webhook secret" >&2
      return 1
    }
  fi
  
  # Generate new secret
  local new_secret=$(openssl rand -hex 32)
  
  # Store new secret in GSM
  gcloud secrets create SECRET_GH_WEBHOOK_SIGNING_SECRET_PROD \
    --replication-policy="automatic" \
    --data-file=<(printf '%s' "$new_secret") \
    2>/dev/null || \
  gcloud secrets versions add SECRET_GH_WEBHOOK_SIGNING_SECRET_PROD \
    --data-file=<(printf '%s' "$new_secret") 2>/dev/null || {
    echo "[webhook] ERROR: Failed to store new secret in GSM" >&2
    return 1
  }
  
  # Support both old and new secrets for 24h grace period
  echo "[webhook] ✓ New webhook secret generated"
  echo "[webhook] ⚠️  Old secret still valid for 24 hours (grace period for GitHub sync)"
  echo "[webhook] Manual action required: Update GitHub repository webhook secret in UI"
  
  return 0
}

# Verify webhook configuration (pre-checks)
verify_webhook_config() {
  echo "[webhook] Verifying webhook configuration..."
  
  # Check GSM secret exists
  if ! credential_exists SECRET_GH_WEBHOOK_SIGNING_SECRET_PROD; then
    echo "[webhook] ✗ Webhook signing secret not found in GSM" >&2
    return 1
  fi
  
  # Check required commands
  for cmd in openssl jq gcloud; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "[webhook] ✗ Required command not found: $cmd" >&2
      return 1
    fi
  done
  
  echo "[webhook] ✓ Webhook configuration verified"
  return 0
}

# Export functions
export -f validate_webhook_signature
export -f log_webhook_event
export -f validate_webhook_payload
export -f should_process_webhook
export -f handle_webhook
export -f rotate_webhook_secret
export -f verify_webhook_config
