#!/bin/bash
# 🏥 HEALTH CHECK & SELF-HEALING AUTOMATION
# Continuous health monitoring, automatic detection, and hands-off remediation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/../logs/health"
mkdir -p "$LOG_DIR"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_DIR/health.log"; }
success() { echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_DIR/health.log"; }
error() { echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_DIR/health.log"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_DIR/health.log"; }
info() { echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_DIR/health.log"; }

# ============================================================================
# CREDENTIAL LAYER HEALTH CHECKS
# ============================================================================

check_gsm_health() {
    local health_status="HEALTHY"
    local error_count=0
    
    info "Checking GSM layer..."
    
    if [ -z "${GCP_PROJECT_ID:-}" ]; then
        warn "GSM not configured (GCP_PROJECT_ID not set)"
        return 0
    fi
    
    # Check GSM connectivity
    if ! gcloud secrets list --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
        error "GSM connectivity failed"
        health_status="UNHEALTHY"
        error_count=$((error_count + 1))
    else
        success "GSM connectivity: OK"
    fi
    
    # Check credential availability
    for secret in terraform-aws-prod terraform-aws-secret terraform-aws-region; do
        if gcloud secrets describe "$secret" --project="$GCP_PROJECT_ID" >/dev/null 2>&1; then
            success "GSM secret available: $secret"
        else
            warn "GSM secret missing: $secret"
            error_count=$((error_count + 1))
        fi
    done
    
    # Check secret rotation age
    last_updated=$(gcloud secrets versions list terraform-aws-prod \
        --project="$GCP_PROJECT_ID" \
        --limit=1 \
        --format='value(created)' 2>/dev/null || echo "unknown")
    
    if [ "$last_updated" != "unknown" ]; then
        days_old=$(($(date +%s) - $(date -d "$last_updated" +%s) / 86400))
        if [ "$days_old" -gt 1 ]; then
            warn "GSM secrets not rotated in $days_old days (rotate daily)"
        fi
    fi
    
    echo "$health_status"
    return "$error_count"
}

check_vault_health() {
    local health_status="HEALTHY"
    
    info "Checking Vault layer..."
    
    if [ -z "${VAULT_ADDR:-}" ]; then
        warn "Vault not configured (VAULT_ADDR not set)"
        return 0
    fi
    
    # Check Vault connectivity
    if ! curl -s "$VAULT_ADDR/v1/sys/health" >/dev/null 2>&1; then
        error "Vault connectivity failed"
        health_status="UNHEALTHY"
        return 1
    fi
    
    success "Vault connectivity: OK"
    
    # Check Vault seal status
    seal_status=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq '.sealed' 2>/dev/null)
    
    if [ "$seal_status" == "false" ]; then
        success "Vault seal status: UNSEALED"
    else
        error "Vault is SEALED - manual intervention required"
        health_status="UNHEALTHY"
        return 1
    fi
    
    # Check AppRole auth
    if curl -s -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
        "$VAULT_ADDR/v1/auth/approle/role/deployment" >/dev/null 2>&1; then
        success "Vault AppRole: AVAILABLE"
    else
        error "Vault AppRole: UNAVAILABLE"
        health_status="UNHEALTHY"
        return 1
    fi
    
    echo "$health_status"
    return 0
}

check_kms_health() {
    local health_status="HEALTHY"
    
    info "Checking KMS layer..."
    
    if [ -z "${AWS_REGION:-}" ]; then
        warn "KMS not configured (AWS_REGION not set)"
        return 0
    fi
    
    # Check KMS connectivity
    if ! aws kms list-keys --region "${AWS_REGION}" >/dev/null 2>&1; then
        error "KMS connectivity failed"
        health_status="UNHEALTHY"
        return 1
    fi
    
    success "KMS connectivity: OK"
    
    # Check key availability
    if [ -n "${KMS_KEY_ID:-}" ]; then
        key_status=$(aws kms describe-key \
            --key-id "$KMS_KEY_ID" \
            --region "${AWS_REGION}" \
            --query 'KeyMetadata.Enabled' \
            --output text 2>/dev/null || echo "unknown")
        
        if [ "$key_status" == "True" ]; then
            success "KMS key: ENABLED"
        else
            error "KMS key: DISABLED"
            health_status="UNHEALTHY"
            return 1
        fi
    fi
    
    echo "$health_status"
    return 0
}

check_service_health() {
    local service="$1"
    
    info "Checking service: $service"
    
    case "$service" in
        vault)
            if curl -s http://localhost:8200/v1/sys/health >/dev/null 2>&1; then
                success "Vault service: HEALTHY"
                return 0
            else
                error "Vault service: UNHEALTHY"
                return 1
            fi
            ;;
        postgres)
            if PGPASSWORD="${POSTGRES_PASSWORD:-runner_password}" \
                psql -h localhost -U runner_user -d runner_db -c "SELECT 1" >/dev/null 2>&1; then
                success "PostgreSQL service: HEALTHY"
                return 0
            else
                error "PostgreSQL service: UNHEALTHY"
                return 1
            fi
            ;;
        redis)
            if redis-cli ping >/dev/null 2>&1; then
                success "Redis service: HEALTHY"
                return 0
            else
                error "Redis service: UNHEALTHY"
                return 1
            fi
            ;;
        minio)
            if curl -s http://localhost:9000/minio/health/live >/dev/null 2>&1; then
                success "MinIO service: HEALTHY"
                return 0
            else
                error "MinIO service: UNHEALTHY"
                return 1
            fi
            ;;
        *)
            warn "Unknown service: $service"
            return 1
            ;;
    esac
}

# ============================================================================
# SELF-HEALING AUTOMATION
# ============================================================================

heal_vault() {
    warn "🔧 Attempting Vault healing..."
    
    # Check if Vault is sealed
    seal_status=$(curl -s "$VAULT_ADDR/v1/sys/health" | jq '.sealed' 2>/dev/null || echo "true")
    
    if [ "$seal_status" == "true" ]; then
        error "Vault is SEALED - requires manual unseal with keys"
        # In production, this would trigger alert/incident creation
        return 1
    fi
    
    # Reinitialize AppRole if needed
    if ! curl -s -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
        "$VAULT_ADDR/v1/auth/approle/role/deployment" >/dev/null 2>&1; then
        
        info "Reinitializing Vault AppRole..."
        
        curl -s -X POST \
            -H "X-Vault-Token: ${VAULT_TOKEN:-}" \
            "$VAULT_ADDR/v1/auth/approle/role/deployment" \
            -d '{"token_ttl":"1h","token_max_ttl":"4h"}' >/dev/null 2>&1
        
        success "Vault AppRole reinitialized"
    fi
    
    return 0
}

heal_kms() {
    warn "🔧 Attempting KMS healing..."
    
    if [ -n "${KMS_KEY_ID:-}" ]; then
        # Enable key if disabled
        key_status=$(aws kms describe-key \
            --key-id "$KMS_KEY_ID" \
            --region "${AWS_REGION}" \
            --query 'KeyMetadata.Enabled' \
            --output text 2>/dev/null || echo "unknown")
        
        if [ "$key_status" != "True" ]; then
            info "Enabling KMS key..."
            aws kms enable-key --key-id "$KMS_KEY_ID" --region "${AWS_REGION}" >/dev/null 2>&1
            success "KMS key enabled"
        fi
    fi
    
    return 0
}

heal_service() {
    local service="$1"
    
    warn "🔧 Attempting to heal service: $service"
    
    case "$service" in
        vault)
            docker-compose restart vault >/dev/null 2>&1 && success "Vault restarted" || error "Failed to restart Vault"
            ;;
        postgres)
            docker-compose restart postgres >/dev/null 2>&1 && success "PostgreSQL restarted" || error "Failed to restart PostgreSQL"
            ;;
        redis)
            docker-compose restart redis >/dev/null 2>&1 && success "Redis restarted" || error "Failed to restart Redis"
            ;;
        minio)
            docker-compose restart minio >/dev/null 2>&1 && success "MinIO restarted" || error "Failed to restart MinIO"
            ;;
        *)
            error "Unknown service: $service"
            return 1
            ;;
    esac
    
    sleep 5
    check_service_health "$service"
}

# ============================================================================
# COMPREHENSIVE HEALTH REPORT
# ============================================================================

generate_health_report() {
    local report_file="$LOG_DIR/health-report-$(date +%s).txt"
    
    cat > "$report_file" << EOF
╔════════════════════════════════════════════════════════════════════════════╗
║          COMPREHENSIVE HEALTH REPORT - $(date -u '+%Y-%m-%d %H:%M:%S UTC')                      ║
╚════════════════════════════════════════════════════════════════════════════╝

CREDENTIAL LAYERS
═════════════════════════════════════════════════════════════════════════════

EOF
    
    # GSM health
    gsm_result=$(check_gsm_health 2>&1)
    echo "GCP Secret Manager (GSM):" >> "$report_file"
    echo "$gsm_result" | tail -5 >> "$report_file"
    echo "" >> "$report_file"
    
    # Vault health
    vault_result=$(check_vault_health 2>&1)
    echo "HashiCorp Vault:" >> "$report_file"
    echo "$vault_result" | tail -5 >> "$report_file"
    echo "" >> "$report_file"
    
    # KMS health
    kms_result=$(check_kms_health 2>&1)
    echo "AWS KMS:" >> "$report_file"
    echo "$kms_result" | tail -5 >> "$report_file"
    echo "" >> "$report_file"
    
    cat >> "$report_file" << 'EOF'

SERVICES
═════════════════════════════════════════════════════════════════════════════

EOF
    
    # Check services
    for service in vault postgres redis minio; do
        if check_service_health "$service" >> "$report_file" 2>&1; then
            echo "$service: ✅ HEALTHY" >> "$report_file"
        else
            echo "$service: ❌ UNHEALTHY" >> "$report_file"
        fi
    done
    
    cat >> "$report_file" << 'EOF'

SYSTEM METRICS
═════════════════════════════════════════════════════════════════════════════

EOF
    
    echo "Disk Usage:" >> "$report_file"
    df -h / | tail -1 >> "$report_file"
    echo "" >> "$report_file"
    
    echo "Memory Usage:" >> "$report_file"
    free -h | grep Mem >> "$report_file"
    echo "" >> "$report_file"
    
    echo "Docker Status:" >> "$report_file"
    docker-compose ps >> "$report_file" 2>&1 || echo "Docker unavailable" >> "$report_file"
    
    cat >> "$report_file" << 'EOF'

RECOMMENDATIONS
═════════════════════════════════════════════════════════════════════════════

EOF
    
    if check_gsm_health >/dev/null 2>&1; then
        echo "✓ GSM layer healthy - no action needed" >> "$report_file"
    else
        echo "⚠ GSM layer unhealthy - manual credential sync needed" >> "$report_file"
    fi
    
    if check_vault_health >/dev/null 2>&1; then
        echo "✓ Vault layer healthy - no action needed" >> "$report_file"
    else
        echo "⚠ Vault layer unhealthy - check connectivity and seal status" >> "$report_file"
    fi
    
    if check_kms_health >/dev/null 2>&1; then
        echo "✓ KMS layer healthy - no action needed" >> "$report_file"
    else
        echo "⚠ KMS layer unhealthy - check AWS credentials and key access" >> "$report_file"
    fi
    
    cat "$report_file"
    return 0
}

# ============================================================================
# MAIN HEALTH CHECK LOOP
# ============================================================================

main() {
    local interval="${1:-300}"  # Default: 5 minutes
    local iteration=0
    
    info "🏥 Health Check Daemon Started (interval: ${interval}s)"
    info "Logs: $LOG_DIR/health.log"
    
    while true; do
        iteration=$((iteration + 1))
        
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        info "Health Check Iteration #$iteration - $(date)"
        
        # Run all checks
        failed_layers=()
        failed_services=()
        
        # Check credential layers
        if ! check_gsm_health >/dev/null 2>&1; then
            failed_layers+=("GSM")
        fi
        
        if ! check_vault_health >/dev/null 2>&1; then
            failed_layers+=("Vault")
            heal_vault || warn "Failed to heal Vault"
        fi
        
        if ! check_kms_health >/dev/null 2>&1; then
            failed_layers+=("KMS")
            heal_kms || warn "Failed to heal KMS"
        fi
        
        # Check services
        for service in vault postgres redis minio; do
            if ! check_service_health "$service" >/dev/null 2>&1; then
                failed_services+=("$service")
                heal_service "$service" || warn "Failed to heal $service"
            fi
        done
        
        # Report status
        if [ ${#failed_layers[@]} -eq 0 ] && [ ${#failed_services[@]} -eq 0 ]; then
            success "All systems HEALTHY ✅"
        else
            error "Issues detected: Layers: ${failed_layers[*]:-none} Services: ${failed_services[*]:-none}"
            
            # Generate detailed report
            generate_health_report
        fi
        
        # Sleep before next check
        info "Next check in ${interval}s..."
        sleep "$interval"
    done
}

# Parse arguments
if [ "${1:-}" == "report" ]; then
    generate_health_report
    exit 0
elif [ "${1:-}" == "once" ]; then
    info "Running single health check..."
    check_gsm_health
    check_vault_health
    check_kms_health
    for service in vault postgres redis minio; do
        check_service_health "$service"
    done
    exit 0
else
    # Run continuous health check
    main "$@"
fi
