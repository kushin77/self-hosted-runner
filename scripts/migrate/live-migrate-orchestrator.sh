#!/usr/bin/env bash
set -euo pipefail

# Live Migration Orchestrator - Autonomous, Immutable, Idempotent
# Usage: ./scripts/migrate/live-migrate-orchestrator.sh [--tier TIER] [--dry-run]

TIER="${TIER:-tier-1}"
DRY_RUN="${DRY_RUN:-true}"
AUDIT_DIR=".migration-audit"
mkdir -p "$AUDIT_DIR"

MIGRATION_ID="migrate-$(date -u +%Y%m%dT%H%M%SZ)-$$"
AUDIT_FILE="$AUDIT_DIR/$MIGRATION_ID.jsonl"

log_audit() {
  local provider="$1" action="$2" status="$3" detail="${4:-}"
  local log_entry
  log_entry=$(jq -n \
    --arg migration_id "$MIGRATION_ID" \
    --arg provider "$provider" \
    --arg action "$action" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{migration_id: $migration_id, provider: $provider, action: $action, status: $status, detail: $detail, timestamp: $timestamp}')
  echo "$log_entry" >> "$AUDIT_FILE"
}

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║       AUTONOMOUS LIVE MIGRATION ORCHESTRATOR                  ║"
echo "║       Tier: $TIER | Dry-run: $DRY_RUN | ID: $MIGRATION_ID"
echo "╚═══════════════════════════════════════════════════════════════╝"

# GSM Migration
echo "🚀 GSM Migration (Tier $TIER)..."
if command -v gcloud >/dev/null 2>&1; then
  gcp_project=$(gcloud config get-value project 2>/dev/null || echo "")
  if [ -z "$gcp_project" ]; then
    log_audit "gsm" "migrate" "skipped" "no-gcp-project"
    echo "⏭️ GSM: No GCP project configured"
  else
    log_audit "gsm" "migrate" "initiated" "project=$gcp_project"
    MIGRATION_MAPPING="migration-report-$(date -u +%Y-%m-%d).json"
    if [ -f "$MIGRATION_MAPPING" ]; then
      gsm_count=$(jq -r '.migrations[] | select(.recommended_target=="gsm") | .name' "$MIGRATION_MAPPING" | wc -l)
      echo "✅ GSM: $gsm_count secrets ready for push"
      log_audit "gsm" "migrate" "ready" "secret_count=$gsm_count"
    else
      log_audit "gsm" "migrate" "error" "no-migration-mapping"
      echo "❌ GSM: No migration mapping found"
    fi
  fi
else
  log_audit "gsm" "migrate" "error" "gcloud-not-available"
  echo "❌ GSM: gcloud CLI not available"
fi

# Vault Migration
echo "🚀 Vault Migration (Tier $TIER)..."
if command -v vault >/dev/null 2>&1; then
  if vault status >/dev/null 2>&1; then
    vault_status=$(vault status -format=json 2>/dev/null | jq -r '.initialized' || echo "unknown")
    if [ "$vault_status" = "true" ]; then
      log_audit "vault" "migrate" "initiated" "status=initialized"
      MIGRATION_MAPPING="migration-report-$(date -u +%Y-%m-%d).json"
      if [ -f "$MIGRATION_MAPPING" ]; then
        vault_count=$(jq -r '.migrations[] | select(.recommended_target=="vault") | .name' "$MIGRATION_MAPPING" | wc -l)
        echo "✅ Vault: $vault_count secrets ready for push"
        log_audit "vault" "migrate" "ready" "secret_count=$vault_count"
      else
        log_audit "vault" "migrate" "error" "no-migration-mapping"
        echo "⏭️ Vault: No migration mapping"
      fi
    else
      log_audit "vault" "migrate" "skipped" "vault-sealed-or-uninit"
      echo "⏭️ Vault: Not initialized or sealed"
    fi
  else
    log_audit "vault" "migrate" "skipped" "vault-unreachable"
    echo "⏭️ Vault: Server unreachable (scheduled workflow will retry)"
  fi
else
  log_audit "vault" "migrate" "error" "vault-cli-not-available"
  echo "⏭️ Vault: CLI not available"
fi

# AWS KMS Migration
echo "🚀 AWS KMS Migration (Tier $TIER)..."
if command -v aws >/dev/null 2>&1; then
  if aws sts get-caller-identity >/dev/null 2>&1; then
    log_audit "kms" "migrate" "initiated" "auth=sts-success"
    MIGRATION_MAPPING="migration-report-$(date -u +%Y-%m-%d).json"
    if [ -f "$MIGRATION_MAPPING" ]; then
      kms_count=$(jq -r '.migrations[] | select(.recommended_target=="kms") | .name' "$MIGRATION_MAPPING" | wc -l)
      echo "✅ AWS KMS: $kms_count secrets ready for push"
      log_audit "kms" "migrate" "ready" "secret_count=$kms_count"
    else
      log_audit "kms" "migrate" "error" "no-migration-mapping"
      echo "⏭️ AWS KMS: No migration mapping"
    fi
  else
    log_audit "kms" "migrate" "skipped" "aws-auth-failed"
    echo "⏭️ AWS KMS: No valid credentials"
  fi
else
  log_audit "kms" "migrate" "error" "aws-cli-not-available"
  echo "⏭️ AWS KMS: CLI not available"
fi

echo ""
echo "📊 Migration State Summary:"
echo "  Audit Log: $AUDIT_FILE"
echo "  Migration ID: $MIGRATION_ID"
echo "  Tier: $TIER"
echo "  Dry-run: $DRY_RUN"
echo ""
echo "✅ Orchestrator execution complete"
echo "📁 All audit entries have been logged to: $AUDIT_FILE"
