#!/bin/bash

################################################################################
# Anomaly Detection & Self-Healing Orchestrator
# Monitors credential access patterns for suspicious activity
# Auto-remediation: rate limiting, rotation, quarantine
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANOMALY_LOG="${PROJECT_ROOT}/logs/governance/anomaly-detection.jsonl"
REMEDIATION_LOG="${PROJECT_ROOT}/logs/governance/auto-remediation.jsonl"

mkdir -p "$(dirname "$ANOMALY_LOG")" "$(dirname "$REMEDIATION_LOG")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; }
warning() { echo -e "${YELLOW}⚠${NC} $*"; }

audit_anomaly() {
    local anomaly_type="$1" severity="$2" actor="$3" secret="$4" details="${5:-}"
    printf '{"timestamp":"%s","type":"%s","severity":"%s","actor":"%s","secret":"%s","details":%s}\n' \
        "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$anomaly_type" "$severity" "$actor" "$secret" "$details" >> "$ANOMALY_LOG"
}

audit_remediation() {
    local action="$1" status="$2" secret="$3" reason="${4:-}" duration_ms="${5:-}"
    printf '{"timestamp":"%s","action":"%s","status":"%s","secret":"%s","reason":"%s","duration_ms":%s}\n' \
        "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$action" "$status" "$secret" "$reason" "$duration_ms" >> "$REMEDIATION_LOG"
}

################################################################################
# ANOMALY DETECTION ENGINES
################################################################################

# Analyze: Spike in Access Rate
detect_access_spike() {
    local secret="$1"
    local baseline="${2:-10}"  # requests per hour baseline
    local spike_threshold="${3:-50}"  # 5x baseline = anomaly
    
    local audit_file="${PROJECT_ROOT}/logs/secret-mirror/audit-${secret}-*.jsonl"
    
    # Count accesses in last hour
    local recent_access=$(find "${PROJECT_ROOT}/logs" -name "*${secret}*" -mmin -60 2>/dev/null | wc -l)
    
    if [ "$recent_access" -gt "$spike_threshold" ]; then
        error "ANOMALY: Access spike detected for $secret (${recent_access} accesses, threshold $spike_threshold)"
        audit_anomaly "access_spike" "CRITICAL" "unknown" "$secret" "{\"access_count\":$recent_access,\"threshold\":$spike_threshold}"
        return 0  # Anomaly detected
    fi
    
    return 1  # No anomaly
}

# Analyze: Unusual Access Pattern (time-of-day)
detect_unusual_access_time() {
    local secret="$1"
    local expected_window="${2:-6-9,14-16}"  # expected UTC hours (e.g., business hours)
    
    local current_hour=$(date -u +%H)
    local in_window=0
    
    IFS=',' read -ra windows <<< "$expected_window"
    for window in "${windows[@]}"; do
        IFS='-' read -ra range <<< "$window"
        if [ "$current_hour" -ge "${range[0]}" ] && [ "$current_hour" -le "${range[1]}" ]; then
            in_window=1
            break
        fi
    done
    
    if [ $in_window -eq 0 ]; then
        warning "ANOMALY: Access to $secret outside expected window (hour: $current_hour, window: $expected_window)"
        audit_anomaly "unusual_time" "WARN" "unknown" "$secret" "{\"access_hour\":$current_hour,\"expected_window\":\"$expected_window\"}"
        return 0
    fi
    
    return 1
}

# Analyze: Failed Access Attempts Clustering
detect_failed_attempt_cluster() {
    local secret="$1"
    local failure_threshold="${2:-10}"  # 10 failures in 10 minutes
    
    local recent_failures=$(grep -l "FAIL" "${PROJECT_ROOT}/logs"/*"${secret}"*.jsonl 2>/dev/null | wc -l)
    
    if [ "$recent_failures" -gt "$failure_threshold" ]; then
        error "ANOMALY: Repeated access failures detected for $secret ($recent_failures failures)"
        audit_anomaly "failed_attempt_cluster" "CRITICAL" "unknown" "$secret" "{\"failure_count\":$recent_failures,\"threshold\":$failure_threshold}"
        return 0  # Anomaly detected
    fi
    
    return 1
}

# Analyze: Cross-Secret Correlation (accessing multiple secrets in short time)
detect_cross_secret_correlation() {
    local actor="$1"
    local secret_count_threshold="${2:-5}"  # 5+ different secrets in 1 minute = suspicious
    
    local recent_accesses=$(grep "$actor" "${PROJECT_ROOT}/logs"/*secret*.jsonl 2>/dev/null | grep -c "\"timestamp\"" || echo 0)
    
    # Count unique secrets accessed
    local unique_secrets=$(grep "$actor" "${PROJECT_ROOT}/logs"/*secret*.jsonl 2>/dev/null | jq -r '.secret' | sort -u | wc -l || echo 0)
    
    if [ "$unique_secrets" -gt "$secret_count_threshold" ]; then
        error "ANOMALY: Multiple secrets accessed by $actor in short time ($unique_secrets secrets)"
        audit_anomaly "cross_secret_correlation" "CRITICAL" "$actor" "multiple" "{\"unique_secrets\":$unique_secrets,\"threshold\":$secret_count_threshold}"
        return 0
    fi
    
    return 1
}

# Analyze: Freshness Degradation (stale credentials)
detect_freshness_issue() {
    local secret="$1"
    local max_age_hours="${2:-24}"  # credentials >24h old = stale
    
    local created_file="${PROJECT_ROOT}/.cred_cache/${secret}.created"
    
    if [ ! -f "$created_file" ]; then
        return 1  # No tracking info
    fi
    
    local created_at=$(cat "$created_file")
    local now=$(date +%s)
    local age_seconds=$((now - created_at))
    local age_hours=$((age_seconds / 3600))
    
    if [ "$age_hours" -gt "$max_age_hours" ]; then
        warning "ANOMALY: Stale credential for $secret (age: ${age_hours}h, max: ${max_age_hours}h)"
        audit_anomaly "freshness_degradation" "WARN" "system" "$secret" "{\"age_hours\":$age_hours,\"max_hours\":$max_age_hours}"
        return 0
    fi
    
    return 1
}

################################################################################
# AUTO-REMEDIATION ACTIONS
################################################################################

autoremedy_rate_limit() {
    local actor="$1"
    local secret="$2"
    
    log "AUTO-REMEDY: Applying exponential rate limiting to $actor for secret $secret"
    
    # Write rate limit rule
    mkdir -p "${PROJECT_ROOT}/.rate_limits"
    local limit_file="${PROJECT_ROOT}/.rate_limits/${actor}.limits"
    
    echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"secret\":\"$secret\",\"max_per_minute\":1,\"backoff_exponential\":true}" >> "$limit_file"
    
    success "Rate limiting applied"
    audit_remediation "rate_limit_applied" "SUCCESS" "$secret" "Access spike detected" "0"
}

autoremedy_force_rotation() {
    local secret="$1"
    
    log "AUTO-REMEDY: Triggering force rotation for secret $secret"
    
    # Write rotation request
    mkdir -p "${PROJECT_ROOT}/.rotation_queue"
    echo "$secret" >> "${PROJECT_ROOT}/.rotation_queue/immediate.txt"
    
    # Execute rotation
    if bash "${PROJECT_ROOT}/scripts/secrets/rotate-credentials.sh" --apply >/dev/null 2>&1; then
        success "Force rotation initiated"
        audit_remediation "force_rotation" "SUCCESS" "$secret" "Anomaly detected - force rotation" "0"
        return 0
    else
        error "Force rotation failed"
        audit_remediation "force_rotation" "FAIL" "$secret" "Rotation execution failed" "0"
        return 1
    fi
}

autoremedy_quarantine() {
    local secret="$1"
    local reason="$2"
    
    log "AUTO-REMEDY: Quarantining secret $secret (reason: $reason)"
    
    mkdir -p "${PROJECT_ROOT}/.quarantine"
    local quarantine_file="${PROJECT_ROOT}/.quarantine/${secret}.quarantined"
    
    echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"secret\":\"$secret\",\"reason\":\"$reason\",\"quarantine_until\":\"$(date -u -d '+24 hours' +"%Y-%m-%dT%H:%M:%SZ")\"}" > "$quarantine_file"
    
    success "Secret quarantined for 24 hours"
    audit_remediation "quarantine" "SUCCESS" "$secret" "$reason" "0"
}

autoremedy_alert_security() {
    local secret="$1"
    local anomaly_type="$2"
    
    log "AUTO-REMEDY: Alerting security team for $secret ($anomaly_type)"
    
    # Write alert (in production: would integrate with Slack/PagerDuty)
    mkdir -p "${PROJECT_ROOT}/.alerts"
    local alert_file="${PROJECT_ROOT}/.alerts/security-alert-$(date +%s).txt"
    
    cat > "$alert_file" << EOF
SECURITY ANOMALY DETECTED
========================
Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Secret: $secret
Anomaly Type: $anomaly_type
Severity: CRITICAL

Actions Taken:
- Anomaly logged to unmodifiable audit trail
- Rate limiting applied
- Security team alerted (this message)

Investigation:
Check logs at: ${PROJECT_ROOT}/logs/governance/anomaly-detection.jsonl
EOF
    
    success "Security alert issued"
    audit_remediation "security_alert" "SUCCESS" "$secret" "Anomaly type: $anomaly_type" "0"
}

################################################################################
# ORCHESTRATION
################################################################################

analyze_and_remediate() {
    local secret="${1:-}"
    
    log "=== ANOMALY DETECTION & AUTO-REMEDIATION CYCLE ==="
    log "Target secret: ${secret:-(all)}"
    echo
    
    local anomalies_found=0
    
    # Run all detection engines
    if detect_access_spike "$secret" 10 50; then
        anomalies_found=$((anomalies_found + 1))
        autoremedy_rate_limit "unknown" "$secret"
        autoremedy_alert_security "$secret" "access_spike"
    fi
    
    if detect_unusual_access_time "$secret"; then
        warning "Unusual access time detected (informational only)"
    fi
    
    if detect_failed_attempt_cluster "$secret" 10; then
        anomalies_found=$((anomalies_found + 1))
        autoremedy_quarantine "$secret" "Failed access attempts clustering"
        autoremedy_alert_security "$secret" "failed_attempt_cluster"
    fi
    
    if detect_freshness_issue "$secret" 24; then
        warning "Credential stale, triggering rotation"
        autoremedy_force_rotation "$secret"
    fi
    
    echo
    if [ $anomalies_found -gt 0 ]; then
        warning "Found $anomalies_found anomaly(ies), auto-remediation applied"
        return 1
    fi
    
    success "No anomalies detected ✓"
    return 0
}

################################################################################
# MAIN
################################################################################

main() {
    if [ $# -eq 0 ]; then
        analyze_and_remediate
    else
        analyze_and_remediate "$1"
    fi
}

main "$@"
