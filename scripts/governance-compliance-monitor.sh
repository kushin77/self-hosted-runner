#!/bin/bash
# ============================================================================
# REAL-TIME COMPLIANCE MONITORING DAEMON
# ============================================================================
# Purpose: Monitor infrastructure for governance violations in real-time
# Deployment: /etc/cron.d/ or systemd timer
# Frequency: Every 5 minutes (default)
# Alert: Kills non-compliant processes and sends alerts
# ============================================================================

set -e

CONTROL_PLANE_IP="192.168.168.31"
WORKER_NODE_IP="192.168.168.42"
CURRENT_HOST=$(hostname -I | awk '{print $1}')
ALERT_WEBHOOK="${SLACK_WEBHOOK_URL:-}"
LOG_DIR="/var/log/governance"
LOG_FILE="${LOG_DIR}/compliance.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Ensure log directory exists (fall back to repo-local logs if /var/log not writable)
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
  LOG_DIR="$(pwd)/logs/governance"
  mkdir -p "$LOG_DIR" || true
  LOG_FILE="${LOG_DIR}/compliance.log"
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_message() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_violation() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] VIOLATION: $1" | tee -a "$LOG_FILE"
  
  if [ -n "$ALERT_WEBHOOK" ]; then
    curl -s -X POST "$ALERT_WEBHOOK" \
      -H 'Content-Type: application/json' \
      -d "{
        \"text\": \"🚨 Infrastructure Governance Violation\",
        \"attachments\": [{
          \"color\": \"danger\",
          \"fields\": [
            {\"title\": \"Host\", \"value\": \"$CURRENT_HOST\", \"short\": true},
            {\"title\": \"Violation\", \"value\": \"$1\", \"short\": false},
            {\"title\": \"Timestamp\", \"value\": \"$(date)\", \"short\": true}
          ]
        }]
      }" || true
  fi
}

# ============================================================================
# VIOLATION CHECKS
# ============================================================================

# Check 1: Node.js services on control plane
check_localhost_services() {
  if [[ "$CURRENT_HOST" == "$CONTROL_PLANE_IP"* ]]; then
    VIOLATIONS=$(ps aux | grep -E 'node|npm|vite|portal' | grep -v grep | grep -v 'governance\|monitoring' || true)
    
    if [ -n "$VIOLATIONS" ]; then
      log_violation "CRITICAL: Node.js services detected on control plane ($CONTROL_PLANE_IP)"
      
      # Kill violating processes
      echo "$VIOLATIONS" | awk '{print $2}' | while read PID; do
        log_violation "Killing process $PID ($(ps -p $PID -o comm=))"
        kill -9 "$PID" 2>/dev/null || true
      done
      
      return 1
    fi
  fi
  return 0
}

# Check 2: Port binding to localhost
check_port_bindings() {
  if [[ "$CURRENT_HOST" == "$CONTROL_PLANE_IP"* ]]; then
    LOCALHOST_PORTS=$(netstat -tlnp 2>/dev/null | grep "127.0.0.1" | grep -v grep || true)
    
    if [ -n "$LOCALHOST_PORTS" ]; then
      echo "$LOCALHOST_PORTS" | while read line; do
        PORT=$(echo "$line" | awk '{print $4}' | cut -d: -f2)
        PID=$(echo "$line" | awk -F'/' '{print $1}' | awk '{print $NF}')
        
        if [[ "$PORT" =~ ^(3919|3000|9095|9096)$ ]]; then
          log_violation "Service port $PORT bound to localhost (should be on $WORKER_NODE_IP)"
          [ -n "$PID" ] && kill -9 "$PID" 2>/dev/null || true
          return 1
        fi
      done
    fi
  fi
  return 0
}

# Check 3: Redis/Database on control plane
check_databases() {
  if [[ "$CURRENT_HOST" == "$CONTROL_PLANE_IP"* ]]; then
    REDIS_PROC=$(ps aux | grep redis-server | grep -v grep || true)
    POSTGRES_PROC=$(ps aux | grep postgres | grep -v grep || true)
    
    if [ -n "$REDIS_PROC" ]; then
      log_violation "CRITICAL: Redis detected on control plane"
      killall redis-server 2>/dev/null || true
      return 1
    fi
    
    if [ -n "$POSTGRES_PROC" ]; then
      log_violation "CRITICAL: PostgreSQL detected on control plane"
      # Note: Be careful with PostgreSQL kills in production
      return 1
    fi
  fi
  return 0
}

# Check 4: Docker containers expected on worker only
check_docker_containers() {
  if [[ "$CURRENT_HOST" == "$CONTROL_PLANE_IP"* ]] && command -v docker &> /dev/null; then
    SERVICE_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null | \
      grep -E 'portal|prometheus|grafana|api|worker' || true)
    
    if [ -n "$SERVICE_CONTAINERS" ]; then
      log_violation "Service containers detected on control plane:"
      echo "$SERVICE_CONTAINERS" | while read container; do
        log_violation "  - Stopping $container"
        docker stop "$container" 2>/dev/null || true
      done
      return 1
    fi
  fi
  return 0
}

# Check 5: Verify worker node services are running
check_worker_services() {
  if [[ "$CURRENT_HOST" == "$WORKER_NODE_IP"* ]]; then
    # Portal service
    if ! curl -s http://localhost:3919 > /dev/null 2>&1; then
      log_violation "WARNING: Portal service (3919) not responding on worker node"
    else
      log_message "✓ Portal service healthy"
    fi
    
    # Prometheus
    if ! curl -s http://localhost:9095 > /dev/null 2>&1; then
      log_violation "WARNING: Prometheus (9095) not responding on worker node"
    else
      log_message "✓ Prometheus healthy"
    fi
    
    # Grafana
    if ! curl -s http://localhost:3000 > /dev/null 2>&1; then
      log_violation "WARNING: Grafana (3000) not responding on worker node"
    fi
  fi
}

# ============================================================================
# EXECUTE CHECKS
# ============================================================================

echo ""
log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_message "Starting compliance monitoring on $CURRENT_HOST"
log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TOTAL_VIOLATIONS=0

check_localhost_services || TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + 1))
check_port_bindings || TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + 1))
check_databases || TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + 1))
check_docker_containers || TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + 1))
check_worker_services || TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + 1))

# ============================================================================
# SUMMARY
# ============================================================================

if [ $TOTAL_VIOLATIONS -eq 0 ]; then
  log_message "✓ All compliance checks passed"
else
  log_message "✗ $TOTAL_VIOLATIONS compliance violations detected and remediated"
fi

log_message "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Return appropriate exit code
exit $([[ $TOTAL_VIOLATIONS -eq 0 ]] && echo 0 || echo 1)
