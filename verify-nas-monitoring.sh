#!/bin/bash
# NAS Host Monitoring Deployment Verification Script
# Validates Prometheus scrape configuration, alert rules, and data collection
# Compliance: Immutable, ephemeral, idempotent, no-ops, hands-off, OAuth-exclusive
#
# Usage: ./verify-nas-monitoring.sh [--verbose] [--test-alerts]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VERBOSE=${1:-""}
TEST_ALERTS=${2:-""}

# Configuration
PROMETHEUS_API="http://192.168.168.42:9090/api/v1"
ALERTMANAGER_API="http://192.168.168.42:9093/api/v1"
NAS_HOST="eiq-nas"
NAS_PORT=9100

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Phase 0: Detect NAS host availability
echo ""
log_info "Phase 0: NAS Host Availability Check"
log_info "======================================="

if ping -c 1 -W 1 "$NAS_HOST" > /dev/null 2>&1; then
    log_success "NAS host reachable: $NAS_HOST"
else
    log_warning "NAS host unreachable via ping (may still be accessible via DNS)"
fi

if curl -s -m 2 "http://$NAS_HOST:$NAS_PORT/metrics" > /dev/null; then
    log_success "Node Exporter accessible: http://$NAS_HOST:$NAS_PORT/metrics"
    METRICS_COUNT=$(curl -s "http://$NAS_HOST:$NAS_PORT/metrics" | grep -c "^[a-z_]" || true)
    log_info "Node Exporter metrics count: ~$METRICS_COUNT"
else
    log_error "Node Exporter NOT accessible: http://$NAS_HOST:$NAS_PORT/metrics"
    log_warning "Deployment cannot proceed without Node Exporter."
    exit 1
fi

# Phase 1: Prometheus Configuration Validation
echo ""
log_info "Phase 1: Prometheus Configuration Validation"
log_info "=============================================="

# Check if Prometheus is running
if curl -s -m 2 "$PROMETHEUS_API/query?query=up" > /dev/null 2>&1; then
    log_success "Prometheus accessible at $PROMETHEUS_API"
else
    log_error "Prometheus NOT accessible at $PROMETHEUS_API"
    log_warning "Cannot verify monitoring setup without Prometheus."
    exit 1
fi

# Verify NAS scrape jobs are configured
SCRAPE_JOBS=("eiq-nas-node-metrics" "eiq-nas-storage-metrics" "eiq-nas-network-metrics" "eiq-nas-process-metrics" "eiq-nas-custom-metrics")

for job in "${SCRAPE_JOBS[@]}"; do
    TARGETS=$(curl -s "$PROMETHEUS_API/targets" | jq -r ".data.activeTargets[] | select(.labels.job==\"$job\") | .scrapeUrl" 2>/dev/null || echo "")
    
    if [[ -n "$TARGETS" ]]; then
        log_success "Scrape job configured: $job"
        [[ "$VERBOSE" == "--verbose" ]] && log_info "  Target URL: $TARGETS"
    else
        log_warning "Scrape job NOT found: $job (may be pending discovery)"
    fi
done

# Phase 2: NAS Metrics Ingestion Verification
echo ""
log_info "Phase 2: NAS Metrics Ingestion Verification"
log_info "==========================================="

# Check if 'up' metric exists for eiq-nas
UP_METRIC=$(curl -s "$PROMETHEUS_API/query?query=up{instance=\"eiq-nas\"}" | jq '.data.result[0].value[1]' 2>/dev/null || echo "null")

if [[ "$UP_METRIC" == "1" ]]; then
    log_success "NAS host is UP (metrics being scraped)"
elif [[ "$UP_METRIC" == "0" ]]; then
    log_error "NAS host is DOWN (scrape failing, check network/firewall)"
    exit 1
else
    log_warning "NAS metrics not yet available (may take 30+ seconds after deployment)"
fi

# Check for each metric category
METRIC_QUERIES=(
    'node_cpu_seconds_total{instance="eiq-nas"}'
    'node_memory_MemTotal_bytes{instance="eiq-nas"}'
    'node_filesystem_size_bytes{instance="eiq-nas"}'
    'node_network_receive_bytes_total{instance="eiq-nas"}'
    'node_procs_running{instance="eiq-nas"}'
)

for metric in "${METRIC_QUERIES[@]}"; do
    RESULT=$(curl -s "$PROMETHEUS_API/query?query=$metric" | jq '.data.result | length' 2>/dev/null || echo "0")
    
    if [[ "$RESULT" -gt 0 ]]; then
        log_success "Metric available: $metric"
    else
        log_warning "Metric NOT available: $metric (may still be initializing)"
    fi
done

# Phase 3: Recording Rules Verification
echo ""
log_info "Phase 3: Recording Rules Verification"
log_info "======================================"

RECORDING_RULES=(
    'nas:cpu:usage_percent:5m_avg'
    'nas:memory:used_percent:5m_avg'
    'nas:storage:used_percent:5m_avg'
    'nas:network:bytes_in:1m_rate'
    'nas:disk:io_bytes_read:1m_rate'
)

for rule in "${RECORDING_RULES[@]}"; do
    RESULT=$(curl -s "$PROMETHEUS_API/query?query=$rule" | jq '.data.result | length' 2>/dev/null || echo "0")
    
    if [[ "$RESULT" -gt 0 ]]; then
        log_success "Recording rule active: $rule"
    else
        log_warning "Recording rule NOT producing data: $rule (check evaluation interval)"
    fi
done

# Phase 4: Alert Rules Verification
echo ""
log_info "Phase 4: Alert Rules Verification"
log_info "=================================="

ALERT_RULES=(
    'NASFilesystemSpaceLow'
    'NASNetworkInterfaceDown'
    'NASCPUUsageCritical'
    'NASHostDown'
)

for alert in "${ALERT_RULES[@]}"; do
    ALERT_INFO=$(curl -s "$PROMETHEUS_API/rules" | jq ".data.groups[].rules[] | select(.name==\"$alert\") | {name:.name, state:.state}" 2>/dev/null || echo "")
    
    if [[ -n "$ALERT_INFO" ]]; then
        ALERT_STATE=$(echo "$ALERT_INFO" | jq -r '.state' 2>/dev/null || echo "unknown")
        log_success "Alert rule defined: $alert (state: $ALERT_STATE)"
    else
        log_warning "Alert rule NOT found: $alert (check rule files loaded)"
    fi
done

# Phase 5: OAuth Protection Verification
echo ""
log_info "Phase 5: OAuth Protection Verification"
log_info "======================================="

# Check OAuth2-Proxy is running
OAUTH_STATUS=$(curl -s -I "http://192.168.168.42:4180/oauth2/health" 2>/dev/null | head -1 || echo "")

if [[ "$OAUTH_STATUS" == *"200"* ]]; then
    log_success "OAuth2-Proxy is operational"
else
    log_warning "OAuth2-Proxy health check inconclusive"
fi

# Check Nginx monitoring router enforces X-Auth
NGINX_CONFIG=$(docker exec nginx-monitoring-router cat /etc/nginx/nginx.conf 2>/dev/null | grep -c "auth_request" || echo "0")

if [[ "$NGINX_CONFIG" -gt 0 ]]; then
    log_success "Nginx X-Auth header enforcement configured"
else
    log_warning "Nginx X-Auth configuration not found (may use different container)"
fi

# Phase 6: Alertmanager Integration
echo ""
log_info "Phase 6: Alertmanager Integration"
log_info "=================================="

if curl -s -m 2 "$ALERTMANAGER_API/status" > /dev/null 2>&1; then
    log_success "Alertmanager accessible at $ALERTMANAGER_API"
    
    # Check if there are any active alerts
    ACTIVE_ALERTS=$(curl -s "$ALERTMANAGER_API/alerts" | jq '.data | length' 2>/dev/null || echo "0")
    log_info "Active alerts: $ACTIVE_ALERTS"
else
    log_warning "Alertmanager NOT accessible"
fi

# Phase 7: Optional Alert Testing
if [[ "$TEST_ALERTS" == "--test-alerts" ]]; then
    echo ""
    log_info "Phase 7: Optional Alert Testing"
    log_info "==============================="
    
    # Trigger test alert by querying with intentional value that triggers alert
    TEST_CONDITION='(node_filesystem_avail_bytes{instance="eiq-nas"} / node_filesystem_size_bytes{instance="eiq-nas"}) < 0.1'
    TEST_RESULT=$(curl -s "$PROMETHEUS_API/query?query=$TEST_CONDITION" | jq '.data.result | length' 2>/dev/null || echo "0")
    
    if [[ "$TEST_RESULT" -gt 0 ]]; then
        log_warning "Test condition NASFilesystemSpaceLow would trigger"
    else
        log_success "NAS filesystem space is healthy (test alert would not trigger)"
    fi
fi

# Summary Report
echo ""
log_info "========================================="
log_success "NAS Monitoring Verification Complete"
log_info "========================================="
echo ""
echo "Summary:"
echo "  - NAS Host: $NAS_HOST"
echo "  - Node Exporter: http://$NAS_HOST:$NAS_PORT/metrics"
echo "  - Prometheus: $PROMETHEUS_API"
echo "  - Alertmanager: $ALERTMANAGER_API"
echo "  - OAuth Protection: OAuth2-Proxy port 4180 + Nginx X-Auth"
echo ""
echo "Next Steps:"
echo "  1. Access Prometheus: http://192.168.168.42:4180/prometheus"
echo "  2. Verify NAS targets: Status → Targets → Filter 'eiq-nas'"
echo "  3. Create Grafana dashboards using pre-computed recording rules"
echo "  4. Monitor alert firing for critical conditions"
echo ""
echo "Documentation: NAS_MONITORING_INTEGRATION.md"
echo ""
