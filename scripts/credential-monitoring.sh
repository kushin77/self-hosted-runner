#!/usr/bin/env bash
# Advanced Credential Monitoring & Metrics
# Real-time tracking of credential health, TTL, usage patterns

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_DIR=".metrics-logs"
AUDIT_DIR=".audit-logs"

mkdir -p "$METRICS_DIR" "$AUDIT_DIR"

# Metric collection
collect_metrics() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local metrics_file="$METRICS_DIR/metrics-$(date +%Y%m%d).jsonl"
    
    # GSM health
    local gsm_health="unknown"
    if [ -n "${GCP_PROJECT_ID:-}" ]; then
        if timeout 5 bash "$SCRIPT_DIR/enhanced-fetch-gsm.sh" "$GCP_PROJECT_ID" "test-key" >/dev/null 2>&1; then
            gsm_health="up"
        else
            gsm_health="down"
        fi
    fi
    
    # Vault health
    local vault_health="unknown"
    if [ -n "${VAULT_ADDR:-}" ]; then
        if timeout 5 curl -s "${VAULT_ADDR}/v1/sys/health" >/dev/null 2>&1; then
            vault_health="up"
        else
            vault_health="down"
        fi
    fi
    
    # KMS health
    local kms_health="unknown"
    if [ -n "${AWS_ROLE_TO_ASSUME:-}" ]; then
        if timeout 5 aws sts get-caller-identity >/dev/null 2>&1; then
            kms_health="up"
        else
            kms_health="down"
        fi
    fi
    
    # Log metric
    local metric_entry=$(jq -n \
        --arg ts "$timestamp" \
        --arg gsm "$gsm_health" \
        --arg vault "$vault_health" \
        --arg kms "$kms_health" \
        '{timestamp: $ts, provider_health: {gsm: $gsm, vault: $vault, kms: $kms}}')
    
    echo "$metric_entry" >> "$metrics_file"
}

# Credential TTL tracking
check_credential_ttl() {
    echo "=== Credential TTL Status ==="
    
    local now=$(date +%s)
    local warning_ttl=$((60 * 30))  # 30 minutes
    
    for cache_file in .credentials-cache/* 2>/dev/null; do
        if [ -f "$cache_file" ]; then
            local age=$(($(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null)))
            local ttl=$((60 - age / 60))  # Assume 60 minute base TTL
            local name=$(basename "$cache_file")
            
            if [ $ttl -lt 0 ]; then
                echo "❌ $name: EXPIRED"
            elif [ $ttl -lt 30 ]; then
                echo "⚠️  $name: WARNING (${ttl}min remaining)"
            else
                echo "✓  $name: OK (${ttl}min remaining)"
            fi
        fi
    done
}

# Provider failover status
check_failover_status() {
    echo ""
    echo "=== Failover Chain Status ==="
    
    local primary_up=false
    local secondary_up=false
    local tertiary_up=false
    
    # Check primary (GSM)
    if [ -n "${GCP_PROJECT_ID:-}" ]; then
        if timeout 5 bash "$SCRIPT_DIR/enhanced-fetch-gsm.sh" "$GCP_PROJECT_ID" "test" >/dev/null 2>&1; then
            echo "✓  Primary (GSM): UP"
            primary_up=true
        else
            echo "✗  Primary (GSM): DOWN"
        fi
    fi
    
    # Check secondary (Vault)
    if [ -n "${VAULT_ADDR:-}" ]; then
        if timeout 5 curl -s "${VAULT_ADDR}/v1/sys/health" >/dev/null 2>&1; then
            echo "✓  Secondary (Vault): UP"
            secondary_up=true
        else
            echo "✗  Secondary (Vault): DOWN"
        fi
    fi
    
    # Check tertiary (KMS)
    if [ -n "${AWS_ROLE_TO_ASSUME:-}" ]; then
        if timeout 5 aws sts get-caller-identity >/dev/null 2>&1; then
            echo "✓  Tertiary (KMS): UP"
            tertiary_up=true
        else
            echo "✗  Tertiary (KMS): DOWN"
        fi
    fi
    
    # Summary
    local up_count=0
    $primary_up && up_count=$((up_count + 1))
    $secondary_up && up_count=$((up_count + 1))
    $tertiary_up && up_count=$((up_count + 1))
    
    echo ""
    if [ $up_count -eq 0 ]; then
        echo "🚨 CRITICAL: All credential providers DOWN - escalation required"
        return 1
    elif [ $up_count -eq 1 ]; then
        echo "⚠️  WARNING: Only 1 provider UP - limited redundancy"
        return 0
    else
        echo "✓  OK: $up_count providers operational (redundancy intact)"
        return 0
    fi
}

# Usage patterns
analyze_usage_patterns() {
    echo ""
    echo "=== Credential Usage Analysis ==="
    
    if [ -f "$AUDIT_DIR"/operations.jsonl ] || [ -f "$AUDIT_DIR"/*.jsonl ]; then
        local total_rotations=$(grep -l "credential_rotation" "$AUDIT_DIR"/*.jsonl 2>/dev/null | xargs grep "credential_rotation" | wc -l)
        local total_accesses=$(grep -l "credential_access" "$AUDIT_DIR"/*.jsonl 2>/dev/null | xargs grep "credential_access" | wc -l)
        local failures=$(grep -l "\"status\": \"error\"" "$AUDIT_DIR"/*.jsonl 2>/dev/null | xargs grep "\"status\": \"error\"" | wc -l)
        
        echo "Total rotations: $total_rotations"
        echo "Total accesses: $total_accesses"
        echo "Failures: $failures"
        
        if [ $failures -eq 0 ]; then
            echo "✓  100% success rate"
        else
            local success_rate=$((100 * (total_rotations - failures) / total_rotations))
            echo "Success rate: ${success_rate}%"
        fi
    fi
}

main() {
    case "${1:-all}" in
        collect)
            collect_metrics
            ;;
        ttl)
            check_credential_ttl
            ;;
        failover)
            check_failover_status
            ;;
        usage)
            analyze_usage_patterns
            ;;
        all)
            collect_metrics
            check_credential_ttl
            check_failover_status
            analyze_usage_patterns
            ;;
        *)
            echo "Usage: $0 {collect|ttl|failover|usage|all}"
            exit 1
            ;;
    esac
}

main "$@"
