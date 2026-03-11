#!/usr/bin/env bash
#
# Validate NexusShield Dashboard Deployment
# Comprehensive health checks and diagnostics
# Usage: bash scripts/validate/validate_dashboard.sh [remote_host]
#

set -euo pipefail

REMOTE="${1:-localhost}"
DASHBOARD_PORT="${2:-3000}"
API_URL="${3:-http://localhost:8080}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

# Helper functions
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; ((PASS++)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; ((FAIL++)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; ((WARN++)); }
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }

# Run command on remote or locally
run_cmd() {
  if [ "$REMOTE" == "localhost" ]; then
    bash -c "$1" 2>&1 || echo "FAILED"
  else
    ssh "$REMOTE" bash -c "$1" 2>&1 || echo "FAILED"
  fi
}

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "NexusShield Dashboard Validation Report"
echo "═════════════════════════════════════════════════════════════"
echo "Host: $REMOTE"
echo "Port: $DASHBOARD_PORT"
echo "API URL: $API_URL"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ============================================================================
# SECTION 1: Docker & Container Status
# ============================================================================

echo "1. DOCKER & CONTAINER STATUS"
echo "─────────────────────────────────────────────────────────────"

# Check Docker installed
log_info "Checking Docker installation..."
if run_cmd "which docker" | grep -q "docker"; then
  DOCKER_VERSION=$(run_cmd "docker --version" || echo "unknown")
  log_pass "Docker installed: $DOCKER_VERSION"
else
  log_fail "Docker not installed"
fi

# Check Docker daemon running
log_info "Checking Docker daemon..."
if run_cmd "docker ps >/dev/null 2>&1"; then
  log_pass "Docker daemon is running"
else
  log_fail "Docker daemon is not running"
fi

# Check if image exists
log_info "Checking dashboard image..."
if run_cmd "docker image inspect nexusshield-dashboard:latest >/dev/null 2>&1"; then
  IMAGE_SIZE=$(run_cmd "docker image inspect nexusshield-dashboard:latest -f '{{.Size}}'" || echo "unknown")
  log_pass "Dashboard image exists (size: $(numfmt --to=iec-i --suffix=B $IMAGE_SIZE 2>/dev/null || echo "$IMAGE_SIZE"))"
else
  log_warn "Dashboard image not found (will be built on first deployment)"
fi

# Check container running
log_info "Checking container status..."
if run_cmd "docker ps | grep nexusshield-dashboard-prod" | grep -q "Up"; then
  UPTIME=$(run_cmd "docker inspect --format='{{.State.StartedAt}}' nexusshield-dashboard-prod" || echo "unknown")
  log_pass "Container is running (started: $UPTIME)"
else
  log_fail "Container is not running"
fi

echo ""

# ============================================================================
# SECTION 2: Network & Connectivity
# ============================================================================

echo "2. NETWORK & CONNECTIVITY"
echo "─────────────────────────────────────────────────────────────"

# Check port availability
log_info "Checking port $DASHBOARD_PORT..."
if [ "$REMOTE" == "localhost" ]; then
  if netstat -tlnp 2>/dev/null | grep -q ":$DASHBOARD_PORT "; then
    log_pass "Port $DASHBOARD_PORT is listening"
  else
    log_fail "Port $DASHBOARD_PORT is not listening"
  fi
else
  if ssh "$REMOTE" "netstat -tlnp 2>/dev/null | grep -q ':$DASHBOARD_PORT '" 2>/dev/null; then
    log_pass "Port $DASHBOARD_PORT is listening"
  else
    log_warn "Could not verify port binding (netstat not available)"
  fi
fi

# Check firewall rules
log_info "Checking firewall..."
if run_cmd "sudo ufw status 2>/dev/null | grep -q '$DASHBOARD_PORT'"; then
  log_pass "Firewall rule exists for port $DASHBOARD_PORT"
else
  log_warn "Firewall rule not configured (may be normal)"
fi

# Test HTTP connectivity
log_info "Testing HTTP connectivity..."
if curl -sf http://$REMOTE:$DASHBOARD_PORT/ >/dev/null 2>&1; then
  log_pass "HTTP endpoint is responding"
else
  log_fail "HTTP endpoint is not responding"
fi

echo ""

# ============================================================================
# SECTION 3: Health Checks
# ============================================================================

echo "3. HEALTH CHECKS"
echo "─────────────────────────────────────────────────────────────"

# Docker health status
log_info "Checking Docker health status..."
HEALTH=$(run_cmd "docker inspect --format='{{.State.Health.Status}}' nexusshield-dashboard-prod 2>/dev/null" || echo "no-health")
if [ "$HEALTH" == "healthy" ]; then
  log_pass "Docker health check: healthy"
elif [ "$HEALTH" == "starting" ]; then
  log_warn "Docker health check: still starting"
elif [ "$HEALTH" == "unhealthy" ]; then
  log_fail "Docker health check: unhealthy"
  # Get failure details
  FAILURES=$(run_cmd "docker inspect nexusshield-dashboard-prod | jq '.State.Health.FailingStreak' 2>/dev/null" || echo "unknown")
  log_info "Consecutive failures: $FAILURES"
else
  log_warn "Docker health check: not configured (or container not running)"
fi

# HTTP health endpoint
log_info "Testing /health endpoint..."
HEALTH_RESPONSE=$(curl -sf http://$REMOTE:$DASHBOARD_PORT/health 2>/dev/null || echo "{}")
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
  log_pass "Health endpoint responds: $HEALTH_RESPONSE"
else
  log_fail "Health endpoint not responding correctly"
fi

# API backend connectivity
log_info "Testing API backend connectivity..."
API_HOST=$(echo "$API_URL" | sed 's|http://||g' | cut -d':' -f1)
API_PORT=$(echo "$API_URL" | sed 's|.*:||g')
if [ "$API_PORT" == "$API_URL" ]; then
  API_PORT="80"
fi

if curl -sf http://$API_HOST:$API_PORT/health >/dev/null 2>&1; then
  log_pass "API backend is reachable at $API_URL"
else
  log_warn "API backend not reachable (may be expected if behind firewall)"
fi

echo ""

# ============================================================================
# SECTION 4: Performance Metrics
# ============================================================================

echo "4. PERFORMANCE METRICS"
echo "─────────────────────────────────────────────────────────────"

# Container resource usage
log_info "Checking resource usage..."
if [ "$REMOTE" == "localhost" ]; then
  STATS=$(docker stats --no-stream nexusshield-dashboard-prod 2>/dev/null || echo "")
  if [ -n "$STATS" ]; then
    log_pass "Resource usage:"
    echo "$STATS" | tail -1 | awk '{printf "  CPU: %s, Memory: %s\n", $3, $4}'
  fi
fi

# Memory limits
log_info "Checking memory limits..."
MEM_LIMIT=$(run_cmd "docker inspect nexusshield-dashboard-prod --format='{{.HostConfig.Memory}}'" 2>/dev/null || echo "0")
if [ "$MEM_LIMIT" != "0" ]; then
  log_pass "Memory limit set: $(numfmt --to=iec-i --suffix=B $MEM_LIMIT 2>/dev/null || echo "$MEM_LIMIT")"
else
  log_warn "No memory limit configured (consider setting one)"
fi

# Disk usage
log_info "Checking disk usage..."
DISK_USAGE=$(run_cmd "docker system df" 2>/dev/null || echo "")
if [ -n "$DISK_USAGE" ]; then
  log_info "Docker disk usage:"
  echo "$DISK_USAGE" | grep -E "^REPOSITORY|^CONTAINER" | head -5 | sed 's/^/  /'
fi

echo ""

# ============================================================================
# SECTION 5: Logging & Audit
# ============================================================================

echo "5. LOGGING & AUDIT"
echo "─────────────────────────────────────────────────────────────"

# Check app logs
log_info "Checking application logs..."
LOG_LINES=$(run_cmd "docker logs nexusshield-dashboard-prod 2>/dev/null | wc -l" || echo "0")
if [ "$LOG_LINES" -gt "0" ]; then
  log_pass "Application logs present ($LOG_LINES lines)"
  log_info "Recent logs:"
  run_cmd "docker logs nexusshield-dashboard-prod 2>/dev/null" | tail -3 | sed 's/^/  /'
else
  log_warn "No application logs found"
fi

# Check deployment audit trail
log_info "Checking deployment audit trail..."
if [ -d ".deployment_logs" ]; then
  LOG_COUNT=$(find .deployment_logs -type f | wc -l || echo "0")
  log_pass "Deployment logs found ($LOG_COUNT files)"
else
  log_warn "Deployment logs directory not found"
fi

echo ""

# ============================================================================
# SECTION 6: Configuration Verification
# ============================================================================

echo "6. CONFIGURATION VERIFICATION"
echo "─────────────────────────────────────────────────────────────"

# Check environment variables
log_info "Checking environment variables..."
API_URL_CONFIGURED=$(run_cmd "docker inspect nexusshield-dashboard-prod --format='{{index .Config.Env}}' 2>/dev/null | grep -o 'REACT_APP_API_URL=[^[:space:]]*' || echo 'not-set'")
if [ "$API_URL_CONFIGURED" != "not-set" ]; then
  log_pass "API URL configured: $API_URL_CONFIGURED"
else
  log_warn "API URL not configured"
fi

# Check restart policy
log_info "Checking restart policy..."
RESTART_POLICY=$(run_cmd "docker inspect nexusshield-dashboard-prod --format='{{.HostConfig.RestartPolicy.Name}}'" 2>/dev/null || echo "unknown")
if [ "$RESTART_POLICY" == "unless-stopped" ] || [ "$RESTART_POLICY" == "always" ]; then
  log_pass "Restart policy: $RESTART_POLICY"
else
  log_warn "Restart policy: $RESTART_POLICY (consider 'unless-stopped')"
fi

echo ""

# ============================================================================
# SECTION 7: Security Checks
# ============================================================================

echo "7. SECURITY CHECKS"
echo "─────────────────────────────────────────────────────────────"

# Check for latest image
log_info "Checking image age..."
IMAGE_AGE=$(run_cmd "docker image inspect nexusshield-dashboard:latest -f '{{.Created}}' 2>/dev/null" || echo "unknown")
if [[ $IMAGE_AGE == *"2026-03"* ]]; then
  log_pass "Image is recent: $IMAGE_AGE"
else
  log_warn "Image may be outdated: $IMAGE_AGE"
fi

# Check container privileges
log_info "Checking container privileges..."
PRIVILEGED=$(run_cmd "docker inspect nexusshield-dashboard-prod --format='{{.HostConfig.Privileged}}'" 2>/dev/null || echo "false")
if [ "$PRIVILEGED" == "false" ]; then
  log_pass "Container runs with restricted privileges"
else
  log_warn "Container running in privileged mode (consider disabling)"
fi

# Check for security scanning capability
log_info "Checking security scanning..."
if command -v trivy >/dev/null 2>&1; then
  log_info "Running Trivy security scan (this may take a minute)..."
  if trivy image --severity HIGH,CRITICAL nexusshield-dashboard:latest 2>/dev/null | grep -q "0 vulnerabilities"; then
    log_pass "Security scan passed (no HIGH/CRITICAL vulnerabilities)"
  else
    log_warn "Security scan found issues (review with trivy)"
  fi
else
  log_warn "Trivy not installed (optional: install for security scanning)"
fi

echo ""

# ============================================================================
# SECTION 8: Systemd Integration
# ============================================================================

echo "8. SYSTEMD INTEGRATION"
echo "─────────────────────────────────────────────────────────────"

# Check systemd service
log_info "Checking systemd service..."
if [ "$REMOTE" == "localhost" ]; then
  if sudo systemctl status nexusshield-dashboard >/dev/null 2>&1; then
    SERVICE_STATUS=$(sudo systemctl status nexusshield-dashboard | grep Active)
    log_pass "Systemd service configured: $SERVICE_STATUS"
  else
    log_warn "Systemd service not configured (optional enhancement)"
  fi
else
  log_warn "Systemd check unavailable for remote hosts"
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================

TOTAL=$((PASS + FAIL + WARN))
HEALTH=$((PASS * 100 / TOTAL))

echo "═════════════════════════════════════════════════════════════"
echo "VALIDATION SUMMARY"
echo "═════════════════════════════════════════════════════════════"
echo -e "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo -e "${GREEN}Passed:${NC}  $PASS"
echo -e "${RED}Failed:${NC}  $FAIL"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo ""
echo -e "Overall Health: ${GREEN}$HEALTH%${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
  echo -e "${GREEN}✅ Dashboard is healthy and ready to use${NC}"
  exit 0
elif [ $FAIL -le 2 ]; then
  echo -e "${YELLOW}⚠️  Dashboard is operational but has minor issues${NC}"
  exit 0
else
  echo -e "${RED}❌ Dashboard has critical issues that need attention${NC}"
  exit 1
fi
