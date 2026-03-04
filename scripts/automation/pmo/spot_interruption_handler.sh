#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions Spot Instance Interruption Handler
# Monitors for AWS EC2 spot interruption notices and gracefully shuts down runners
# Designed to run as a systemd service
#
# Usage: ./spot_interruption_handler.sh
#
# Dependencies:
#   - curl
#   - systemctl
#   - jq (optional, for JSON parsing)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/spot_interruption_handler.log"
METRICS_PORT=9102

# Create log directory
mkdir -p "$LOG_DIR"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# AWS EC2 Spot Interruption Notice (AWS Metadata Service)
check_spot_termination_notice() {
  local token
  local response
  
  # Get IMDSv2 token
  token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null || echo "")
  
  if [ -z "$token" ]; then
    return 1  # Not on AWS or metadata service unavailable
  fi
  
  # Check for spot termination notice
  response=$(curl -s -H "X-aws-ec2-metadata-token: $token" \
    "http://169.254.169.254/latest/meta-data/spot/instance-action" 2>/dev/null || echo "")
  
  if [ -n "$response" ]; then
    log "CRITICAL: Spot interruption notice received!"
    log "Response: $response"
    return 0
  fi
  
  return 1
}

# Gracefully shutdown all running runners
shutdown_runners() {
  log "Initiating graceful runner shutdown..."
  
  # Stop all actions.runner.* services
  if systemctl list-units --all --type=service | grep -q "actions.runner"; then
    log "Stopping runner services..."
    systemctl stop 'actions.runner.*' || true
    sleep 10
  fi
  
  log "Runner shutdown complete"
}

# Expose metrics for Prometheus
expose_metrics() {
  local spot_status="$1"  # 0 = normal, 1 = interruption notice
  
  cat > /tmp/spot_metrics.prom.$$ <<EOF
# HELP spot_instance_state Current state of spot instance
# TYPE spot_instance_state gauge
spot_instance_state{instance="$(hostname)",status="$([ "$spot_status" -eq 0 ] && echo "normal" || echo "interrupted")"} $spot_status

# HELP spot_termination_time Unix timestamp of interruption notice
# TYPE spot_termination_time gauge
spot_termination_time $(date +%s)
EOF
  
  mv /tmp/spot_metrics.prom.$$ /tmp/spot_metrics.prom
}

# Main loop
main() {
  log "Spot interruption handler started (PID: $$)"
  
  while true; do
    if check_spot_termination_notice; then
      log "Spot interruption detected, initiating shutdown..."
      expose_metrics 1
      shutdown_runners
      
      # Exit after shutdown attempt (container/instance will terminate)
      log "Exiting after spot interruption handling"
      exit 0
    fi
    
    expose_metrics 0
    sleep 10
  done
}

# Trap signals for graceful shutdown
trap 'log "Received interrupt signal"; exit 0' SIGINT SIGTERM

main
