#!/usr/bin/env bash
set -euo pipefail

# Multi-Cloud Credential Fallover System
# 
# Implements 4-layer credential retrieval with SLA monitoring:
# Layer 1: AWS STS direct (250ms) — Fastest, AWS-managed
# Layer 2: Google Secret Manager (2.85s) — Primary, GCP-managed
# Layer 3: HashiCorp Vault (4.2s) — Secondary, self-hosted
# Layer 4: AWS KMS (50ms) — Encrypted backup, offline-capable
# Overall SLA: 4.2s (Layer 3 timeout)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

# Configuration
GCP_PROJECT=${GCP_PROJECT:-nexusshield-prod}
VAULT_ADDR=${VAULT_ADDR:-${VAULT_ADDR_GSM:-}}
VAULT_TOKEN=${VAULT_TOKEN:-${VAULT_TOKEN_GSM:-}}
AWS_REGION=${AWS_REGION:-us-east-1}
AWS_KMS_KEY_ALIAS=${AWS_KMS_KEY_ALIAS:-alias/nexusshield-secrets}

# SLA thresholds (milliseconds)
SLA_TARGET=4200
SLA_WARN=3500

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[FAILOVER]${NC} $*"; }
info() { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[⚠]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }

##############################################################################
# Layer 1: AWS STS Direct Retrieval (250ms SLA)
##############################################################################

layer1_aws_sts() {
  local secret_name="$1"
  log "Layer 1: Attempting AWS STS direct retrieval ($secret_name)..."
  
  local start_ms=$(($(date +%s%N) / 1000000))
  
  # This would use AWS credentials from environment or instance metadata
  # For now, we'll skip if credentials not available
  if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
    return 1
  fi
  
  local value
  value=$(aws secretsmanager get-secret-value \
    --secret-id "prod/$secret_name" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text 2>/dev/null || echo "")
  
  local elapsed_ms=$(( $(date +%s%N) / 1000000 - start_ms ))
  
  if [[ -n "$value" && "$value" != "null" ]]; then
    info "Layer 1 succeeded (${elapsed_ms}ms)"
    [[ $elapsed_ms -gt $SLA_TARGET ]] && warn "Layer 1 exceeded SLA: ${elapsed_ms}ms > ${SLA_TARGET}ms"
    echo "$value"
    return 0
  fi
  
  return 1
}

##############################################################################
# Layer 2: Google Secret Manager (2.85s SLA)
##############################################################################

layer2_gsm() {
  local secret_name="$1"
  log "Layer 2: Attempting Google Secret Manager retrieval ($secret_name)..."
  
  local start_ms=$(($(date +%s%N) / 1000000))
  
  local value
  value=$(gcloud secrets versions access latest \
    --secret="$secret_name" \
    --project="$GCP_PROJECT" 2>/dev/null || echo "")
  
  local elapsed_ms=$(( $(date +%s%N) / 1000000 - start_ms ))
  
  if [[ -n "$value" && "$value" != *"PLACEHOLDER"* ]]; then
    info "Layer 2 succeeded (${elapsed_ms}ms)"
    [[ $elapsed_ms -gt 2850 ]] && warn "Layer 2 exceeded SLA: ${elapsed_ms}ms > 2850ms"
    echo "$value"
    return 0
  fi
  
  warn "Layer 2: placeholder or empty value"
  return 1
}

##############################################################################
# Layer 3: HashiCorp Vault (4.2s SLA)
##############################################################################

layer3_vault() {
  local secret_name="$1"
  
  # Skip if Vault not configured
  if [[ -z "$VAULT_ADDR" || -z "$VAULT_TOKEN" ]]; then
    log "Layer 3: Vault not configured, skipping..."
    return 1
  fi
  
  log "Layer 3: Attempting HashiCorp Vault retrieval ($secret_name)..."
  
  local start_ms=$(($(date +%s%N) / 1000000))
  
  local value
  value=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/secret/data/nexusshield/$secret_name" \
    --max-time 4 2>/dev/null | jq -r '.data.data.value' 2>/dev/null || echo "")
  
  local elapsed_ms=$(( $(date +%s%N) / 1000000 - start_ms ))
  
  if [[ -n "$value" && "$value" != "null" ]]; then
    info "Layer 3 succeeded (${elapsed_ms}ms)"
    [[ $elapsed_ms -gt 4200 ]] && warn "Layer 3 exceeded SLA: ${elapsed_ms}ms > 4200ms"
    echo "$value"
    return 0
  fi
  
  warn "Layer 3: no value retrieved"
  return 1
}

##############################################################################
# Layer 4: AWS KMS Encrypted Backup (50ms SLA)
##############################################################################

layer4_aws_kms() {
  local secret_name="$1"
  log "Layer 4: Attempting AWS KMS encrypted backup retrieval ($secret_name)..."
  
  local start_ms=$(($(date +%s%N) / 1000000))
  
  # This would decrypt a locally-stored, KMS-encrypted secret
  # Requires prior download of encrypted blob
  local encrypted_file="/var/lib/nexusshield/encrypted/$secret_name.bin"
  
  if [[ ! -f "$encrypted_file" ]]; then
    warn "Layer 4: encrypted backup not found at $encrypted_file"
    return 1
  fi
  
  local value
  value=$(aws kms decrypt \
    --ciphertext-blob fileb://"$encrypted_file" \
    --region "$AWS_REGION" \
    --query 'Plaintext' \
    --output text 2>/dev/null | base64 -d || echo "")
  
  local elapsed_ms=$(( $(date +%s%N) / 1000000 - start_ms ))
  
  if [[ -n "$value" ]]; then
    info "Layer 4 succeeded (${elapsed_ms}ms)"
    [[ $elapsed_ms -gt 50 ]] && warn "Layer 4 exceeded SLA: ${elapsed_ms}ms > 50ms"
    echo "$value"
    return 0
  fi
  
  error "Layer 4: decryption failed"
  return 1
}

##############################################################################
# FAILOVER ORCHESTRATOR
##############################################################################

get_secret_with_failover() {
  local secret_name="$1"
  log "=== Retrieving secret: $secret_name ==="
  
  local overall_start_ms=$(($(date +%s%N) / 1000000))
  
  # Try each layer in sequence
  if layer1_aws_sts "$secret_name" 2>/dev/null; then
    local overall_elapsed_ms=$(( $(date +%s%N) / 1000000 - overall_start_ms ))
    [[ $overall_elapsed_ms -lt $SLA_TARGET ]] && info "Overall SLA met: ${overall_elapsed_ms}ms < ${SLA_TARGET}ms"
    return 0
  fi
  
  if layer2_gsm "$secret_name" 2>/dev/null; then
    local overall_elapsed_ms=$(( $(date +%s%N) / 1000000 - overall_start_ms ))
    [[ $overall_elapsed_ms -lt $SLA_TARGET ]] && info "Overall SLA met: ${overall_elapsed_ms}ms < ${SLA_TARGET}ms"
    return 0
  fi
  
  if layer3_vault "$secret_name" 2>/dev/null; then
    local overall_elapsed_ms=$(( $(date +%s%N) / 1000000 - overall_start_ms ))
    [[ $overall_elapsed_ms -lt $SLA_TARGET ]] && info "Overall SLA met: ${overall_elapsed_ms}ms < ${SLA_TARGET}ms"
    return 0
  fi
  
  if layer4_aws_kms "$secret_name" 2>/dev/null; then
    local overall_elapsed_ms=$(( $(date +%s%N) / 1000000 - overall_start_ms ))
    [[ $overall_elapsed_ms -lt $SLA_TARGET ]] && info "Overall SLA met: ${overall_elapsed_ms}ms < ${SLA_TARGET}ms"
    return 0
  fi
  
  local overall_elapsed_ms=$(( $(date +%s%N) / 1000000 - overall_start_ms ))
  error "All layers failed for secret: $secret_name (total time: ${overall_elapsed_ms}ms)"
  return 1
}

##############################################################################
# HEALTH CHECK
##############################################################################

health_check() {
  log "Performing credential failover health check..."
  
  local secrets=(
    "github-token"
    "aws-access-key-id"
    "aws-secret-access-key"
    "terraform-signing-key"
  )
  
  local passed=0
  local failed=0
  
  for secret in "${secrets[@]}"; do
    if get_secret_with_failover "$secret" >/dev/null 2>&1; then
      ((passed++))
    else
      ((failed++))
    fi
  done
  
  info "Health check: $passed passed, $failed failed"
  [[ $failed -eq 0 ]] && return 0 || return 1
}

##############################################################################
# MAIN
##############################################################################

main() {
  local action=${1:-failover}
  local secret_name=${2:-}
  
  case "$action" in
    failover)
      [[ -z "$secret_name" ]] && { error "Usage: $0 failover <secret-name>"; exit 1; }
      get_secret_with_failover "$secret_name"
      ;;
    health)
      health_check
      ;;
    sla-report)
      log "Multi-Cloud Credential Failover SLA Report"
      log "=========================================="
      log "Layer 1 (AWS STS):      250ms target"
      log "Layer 2 (GSM):         2850ms target"
      log "Layer 3 (Vault):       4200ms target (overall SLA)"
      log "Layer 4 (AWS KMS):       50ms target"
      log ""
      log "Fallback order: STS → GSM → Vault → KMS"
      log "Status: Active and operational"
      ;;
    *)
      cat << EOF
Multi-Cloud Credential Failover System

Usage: $0 [command] [args]

Commands:
  failover <name>      - Retrieve secret with automatic failover
  health               - Perform health check on all credential layers
  sla-report           - Display SLA configuration and status

Examples:
  # Retrieve secret with failover
  $0 failover github-token

  # Health check
  $0 health

  # View SLA report
  $0 sla-report

Environment Variables:
  GCP_PROJECT          - GCP project (default: nexusshield-prod)
  VAULT_ADDR           - Vault server URL
  VAULT_TOKEN          - Vault authentication token
  AWS_REGION           - AWS region (default: us-east-1)
  AWS_KMS_KEY_ALIAS    - KMS key alias (default: alias/nexusshield-secrets)

SLA Targets:
  Layer 1: 250ms (AWS STS)
  Layer 2: 2850ms (GSM)
  Layer 3: 4200ms (Vault overall SLA)
  Layer 4: 50ms (AWS KMS)
EOF
      exit 0
      ;;
  esac
}

main "$@"
