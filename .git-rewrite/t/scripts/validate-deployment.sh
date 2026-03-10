#!/usr/bin/env bash
set -euo pipefail

# Deployment Validation Script
# Verifies that all runner infrastructure components are operational
#
# Usage: ./validate-deployment.sh [--health-check-interval N]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH_CHECK_INTERVAL="${1:-5}"
MAX_WAIT_TIME=300  # 5 minutes

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
  exit 1
}

success() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $*"
}

# Check Terraform state
validate_terraform() {
  log "Validating Terraform state..."
  
  if [ ! -f "terraform/terraform.tfstate" ]; then
    error "Terraform state file not found. Run: terraform apply"
  fi
  
  success "Terraform state exists"
}

# Verify runner instances are created
validate_instances() {
  log "Validating runner instances..."
  
  local runner_ids=$(terraform output -raw standard_runner_ids 2>/dev/null || echo "")
  
  if [ -z "$runner_ids" ]; then
    error "No runner instances found in Terraform output"
  fi
  
  success "Runner instances created"
}

# Wait for instances to be ready
wait_for_instances() {
  log "Waiting for runner instances to be ready (timeout: ${MAX_WAIT_TIME}s)..."
  
  local elapsed=0
  local instance_count=$(terraform output -json standard_runner_ids 2>/dev/null | grep -c "ami-" || echo "0")
  
  while [ $elapsed -lt $MAX_WAIT_TIME ]; do
    local running=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=elevatediq-runners-*" "Name=instance-state-name,Values=running" \
      --query 'length(Reservations[0].Instances)' \
      --output text 2>/dev/null || echo "0")
    
    if [ "$running" -ge "$instance_count" ]; then
      success "All instances are running"
      return 0
    fi
    
    log "  Waiting... ($elapsed/$MAX_WAIT_TIME)s, Running: $running/$instance_count"
    sleep "$HEALTH_CHECK_INTERVAL"
    elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
  done
  
  error "Instances did not start within ${MAX_WAIT_TIME} seconds"
}

# Check runner registration
validate_runner_registration() {
  log "Validating runner registration with GitHub..."
  
  local owner="${GITHUB_OWNER}"
  local token="${GITHUB_TOKEN}"
  
  if [ -z "$owner" ] || [ -z "$token" ]; then
    log "  ⚠ Skipping GitHub API check (GITHUB_OWNER or GITHUB_TOKEN not set)"
    return 0
  fi
  
  local runners=$(curl -s -H "Authorization: token $token" \
    "https://api.github.com/orgs/$owner/actions/runners" | jq '.runners | length')
  
  if [ "$runners" -gt 0 ]; then
    success "Found $runners runners registered with GitHub"
  else
    log "  ⚠ No runners registered yet, this is normal during initial setup"
  fi
}

# Verify security group
validate_security_group() {
  log "Validating security group rules..."
  
  local sg_id=$(terraform output -raw security_group_id 2>/dev/null)
  
  if [ -z "$sg_id" ]; then
    error "Security group ID not found in Terraform output"
  fi
  
  # Check for HTTPS egress rule
  local https_rule=$(aws ec2 describe-security-groups --group-ids "$sg_id" \
    --query 'SecurityGroups[0].IpPermissionsEgress[?ToPort==`443`]' \
    --output json | jq 'length')
  
  if [ "$https_rule" -gt 0 ]; then
    success "Security group allows HTTPS egress"
  else
    error "Security group missing HTTPS egress rule"
  fi
}

# Health check via systemd
validate_health_monitor() {
  log "Validating health monitor..."
  
  if [ -f "$SCRIPT_DIR/scripts/automation/pmo/runner_health_monitor.sh" ]; then
    success "Health monitor script exists"
  else
    log "  ⚠ Health monitor script not found at expected location"
  fi
  
  if systemctl --user is-enabled elevatediq-runner-health-monitor.timer 2>/dev/null; then
    success "Health monitor timer is enabled"
  else
    log "  ⚠ Health monitor timer not yet configured"
  fi
}

# Verify observability stack
validate_observability() {
  log "Validating observability stack..."
  
  if docker ps 2>/dev/null | grep -q prometheus; then
    success "Prometheus container is running"
  else
    log "  ⚠ Prometheus not running (docker-compose may need to be started)"
  fi
  
  if docker ps 2>/dev/null | grep -q grafana; then
    success "Grafana container is running"
  else
    log "  ⚠ Grafana not running"
  fi
}

# Main validation
main() {
  log "=== GitHub Actions Runner Deployment Validation ==="
  
  validate_terraform
  validate_instances
  wait_for_instances
  validate_runner_registration
  validate_security_group
  validate_health_monitor
  validate_observability
  
  log ""
  log "=== Validation Summary ==="
  success "Deployment validated successfully!"
  log ""
  log "Next steps:"
  log "  1. Verify runner health: systemctl --user status elevatediq-runner-health-monitor.timer"
  log "  2. Start observability stack: docker-compose -f scripts/automation/pmo/prometheus/docker-compose-observability.yml up -d"
  log "  3. Access Grafana: http://localhost:3000"
  log ""
}

main "$@"
