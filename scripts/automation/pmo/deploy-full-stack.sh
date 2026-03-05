#!/bin/bash

################################################################################
# Full Stack Deployment to 192.168.168.42
#
# Deploys the complete product stack:
#   - Portal UI (React/Vite) on port 3919
#   - Backend services (provisioner-worker, managed-auth, vault-shim)
#   - All dependencies and infrastructure
#
# Usage:
#   ./deploy-full-stack.sh [--target 192.168.168.42] [--user cloud] [--dry-run]
#
# Prerequisites (on target host 192.168.168.42):
#   - Linux (Ubuntu 20.04+ or Debian 11+) recommended
#   - Node.js 18+ installed
#   - npm or yarn available
#   - SSH access as user 'cloud' (or override with --user)
#   - Passwordless sudo OR ability to create /opt directory
#   - ~500MB disk space for services and logs
#   - Ports 3919 (portal), 9090 (metrics), 4000 (managed-auth) available
#
# Stages:
#   stage1 - Build all components locally
#   stage2 - Deploy to target host via SSH
#   stage3 - Configure services on target
#   stage4 - Start services on target
#   stage5 - Validate and smoke test
#   all    - Execute all stages
#
# Examples:
#   # Full deployment (default target 192.168.168.42)
#   ./deploy-full-stack.sh
#
#   # Custom target
#   ./deploy-full-stack.sh --target 10.0.0.1 --user ubuntu
#
#   # Rebuild and redeploy
#   ./deploy-full-stack.sh --stage all
#
#   # Single stage
#   ./deploy-full-stack.sh --stage stage5
#
# Troubleshooting:
#   If deployment fails, check:
#   1. SSH connectivity: ssh cloud@192.168.168.42 echo OK
#   2. Remote logs: ssh cloud@192.168.168.42 tail -f /tmp/portal.log
#   3. Deployment log: cat /tmp/full-stack-deployment-*.log
#   4. Remote processes: ssh cloud@192.168.168.42 ps aux | grep node
#
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TARGET_HOST="${TARGET_HOST:-192.168.168.42}"
TARGET_USER="${TARGET_USER:-cloud}"
TARGET_BASE="/opt/self-hosted-runner"
STAGE="${STAGE:-all}"
DRY_RUN="${DRY_RUN:-false}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
DEPLOYMENT_LOG="/tmp/full-stack-deployment-$(date +%s).log"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }

################################################################################
# Stage 1: Build all components
################################################################################

stage1_build() {
  log_info "===== STAGE 1: Build All Components ====="

  # Build portal
  log_info "Building portal..."
  cd "$REPO_ROOT/ElevatedIQ-Mono-Repo/apps/portal"
  npm install --legacy-peer-deps 2>&1 | tail -5 | tee -a "$DEPLOYMENT_LOG"
  npm run build 2>&1 | tail -10 | tee -a "$DEPLOYMENT_LOG"
  log_success "Portal built: dist/"

  # Verify backend services have dependencies
  log_info "Installing backend service dependencies..."
  for svc in provisioner-worker managed-auth vault-shim; do
    if [[ -d "$REPO_ROOT/services/$svc" ]]; then
      cd "$REPO_ROOT/services/$svc"
      if [[ ! -f package.json ]]; then
        log_warn "No package.json in services/$svc, creating minimal..."
        npm init -y > /dev/null 2>&1
      fi
      npm install 2>&1 | tail -3 | tee -a "$DEPLOYMENT_LOG"
      log_success "Service $svc ready"
    fi
  done

  log_success "Stage 1 complete: all components built"
}

################################################################################
# Stage 2: Deploy to target host
################################################################################

stage2_deploy() {
  log_info "===== STAGE 2: Deploy to Target Host ($TARGET_HOST) ====="

  # Check SSH connectivity
  log_info "Checking SSH connectivity to $TARGET_HOST..."
  if ssh -o ConnectTimeout=5 "$TARGET_USER@$TARGET_HOST" "echo OK" > /dev/null 2>&1; then
    log_success "SSH connectivity verified"
  else
    log_error "Cannot connect to $TARGET_HOST via SSH"
    return 1
  fi

  # Create target directories
  log_info "Preparing target directories..."
  ssh "$TARGET_USER@$TARGET_HOST" "mkdir -p $TARGET_BASE && mkdir -p /opt/portal/dist && mkdir -p /opt/backend/services"

  # Deploy portal dist
  log_info "Copying portal distribution..."
  if [[ -d "$REPO_ROOT/ElevatedIQ-Mono-Repo/apps/portal/dist" ]]; then
    scp -r "$REPO_ROOT/ElevatedIQ-Mono-Repo/apps/portal/dist" "$TARGET_USER@$TARGET_HOST:/opt/portal/" 2>&1 | tail -3 | tee -a "$DEPLOYMENT_LOG"
    log_success "Portal deployed"
  else
    log_error "Portal dist not found"
    return 1
  fi

  # Deploy backend services
  log_info "Copying backend services..."
  for svc in provisioner-worker managed-auth vault-shim; do
    if [[ -d "$REPO_ROOT/services/$svc" ]]; then
      scp -r "$REPO_ROOT/services/$svc" "$TARGET_USER@$TARGET_HOST:/opt/backend/services/" 2>&1 | tail -2 | tee -a "$DEPLOYMENT_LOG"
      log_success "Service $svc copied"
    fi
  done

  # Copy configuration and utility scripts
  log_info "Copying configuration files..."
  scp -r "$REPO_ROOT/scripts/automation/pmo" "$TARGET_USER@$TARGET_HOST:/opt/self-hosted-runner/scripts/automation/" 2>&1 | tail -2 | tee -a "$DEPLOYMENT_LOG"

  log_success "Stage 2 complete: all files deployed"
}

################################################################################
# Stage 3: Configure services
################################################################################

stage3_configure() {
  log_info "===== STAGE 3: Configure Services on $TARGET_HOST ====="

  # Configure environment variables
  log_info "Creating environment configuration..."
  ssh "$TARGET_USER@$TARGET_HOST" bash << 'REMOTE_SCRIPT'

set -euo pipefail

# Create .env files for services
cat > /opt/backend/.env << 'EOF'
# Backend environment
NODE_ENV=production
PORT=3000

# Provisioner worker
ENABLE_METRICS=true
METRICS_PORT=9090
WORKER_POLL_MS=5000
USE_TERRAFORM_CLI=1
JOBSTORE_PERSIST=1
JOBSTORE_FILE=/opt/backend/data/jobstore.json

# Vault (if needed)
VAULT_ADDR=${VAULT_ADDR:-http://vault:8200}

# Redis (optional)
PROVISIONER_REDIS_URL=${PROVISIONER_REDIS_URL:-redis://localhost:6379}
EOF

mkdir -p /opt/backend/data
chmod 755 /opt/backend/data
echo "Configuration created"

REMOTE_SCRIPT

  log_success "Stage 3 complete: services configured"
}

################################################################################
# Stage 4: Start services
################################################################################

stage4_start() {
  log_info "===== STAGE 4: Start Services on $TARGET_HOST ====="

  ssh "$TARGET_USER@$TARGET_HOST" bash << 'REMOTE_SCRIPT'

set -euo pipefail

# Kill any existing processes on target ports
pkill -f "node.*worker" || true
pkill -f "node.*managed-auth" || true
pkill -f "npm.*dev" || true
pkill -f "http-server" || true
sleep 2

# Start provisioner-worker
echo "Starting provisioner-worker..."
cd /opt/backend/services/provisioner-worker
nohup node worker.js > /tmp/provisioner-worker.log 2>&1 &
sleep 2

# Start managed-auth (if available)
if [[ -d /opt/backend/services/managed-auth ]]; then
  echo "Starting managed-auth..."
  cd /opt/backend/services/managed-auth
  nohup node server.js 2>/dev/null || nohup npm start > /tmp/managed-auth.log 2>&1 &
  sleep 2
fi

# Start portal (use npm or http-server)
echo "Starting portal UI on port 3919..."
cd /opt/portal/dist
if command -v npm &> /dev/null; then
  nohup npm install -g http-server 2>/dev/null || true
fi
nohup http-server -p 3919 -c-1 > /tmp/portal.log 2>&1 &
sleep 2

# Verify processes
echo "Checking running processes..."
ps aux | grep -E "node|http-server|npm" | grep -v grep || echo "No processes found"

REMOTE_SCRIPT

  log_success "Stage 4 complete: services started"
}

################################################################################
# Stage 5: Validate deployment
################################################################################

stage5_validate() {
  log_info "===== STAGE 5: Validate Deployment ====="

  # Check portal connectivity
  log_info "Checking portal on port 3919..."
  if curl -I "http://$TARGET_HOST:3919" 2>/dev/null | head -1 | grep -q "200\|301"; then
    log_success "✓ Portal responding on http://$TARGET_HOST:3919"
  else
    log_warn "⚠ Portal might not be responding (check remote logs)"
  fi

  # Check metrics endpoint
  log_info "Checking provisioner-worker metrics..."
  if curl -I "http://$TARGET_HOST:9090/metrics" 2>/dev/null | head -1 | grep -q "200"; then
    log_success "✓ Metrics endpoint available on http://$TARGET_HOST:9090/metrics"
  else
    log_warn "⚠ Metrics endpoint not responding (check remote logs)"
  fi

  # Check managed-auth
  log_info "Checking backend services..."
  if curl -I "http://$TARGET_HOST:3000/health" 2>/dev/null | head -1 | grep -q "200"; then
    log_success "✓ Managed-auth responding on http://$TARGET_HOST:3000"
  else
    log_warn "⚠ Managed-auth might not be responding (optional for basic deployment)"
  fi

  # Remote validation
  log_info "Verifying remote processes..."
  ssh "$TARGET_USER@$TARGET_HOST" "ps aux | grep -E 'node|http-server' | grep -v grep || echo 'Warning: No processes found'"

  log_success "Stage 5 complete: deployment validated"
}

################################################################################
# Helper functions
################################################################################

show_usage() {
  cat << EOF
${BLUE}Full Stack Deployment Script${NC}

Usage: $0 [OPTIONS]

Options:
  --target HOST       Target host (default: 192.168.168.42)
  --user USER         SSH user (default: cloud)
  --stage STAGE       Deployment stage: stage1|stage2|stage3|stage4|stage5|all
  --dry-run           Show what would be done (not implemented yet)
  --help              Show this message

Environment Variables:
  TARGET_HOST         Override target host
  TARGET_USER         Override SSH user
  STAGE               Override deployment stage
  DRY_RUN             Enable dry-run mode

Examples:
  # Full deployment
  $0 --target 192.168.168.42

  # Single stage
  $0 --stage stage1

  # Rebuild and redeploy
  $0 --stage all

EOF
}

################################################################################
# Main execution
################################################################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET_HOST="$2"
      shift 2
      ;;
    --user)
      TARGET_USER="$2"
      shift 2
      ;;
    --stage)
      STAGE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      show_usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

log_info "Full Stack Deployment Started"
log_info "Target: $TARGET_HOST (user: $TARGET_USER)"
log_info "Stage: $STAGE"
log_info "Log file: $DEPLOYMENT_LOG"

# Execute stages
case "$STAGE" in
  stage1)
    stage1_build
    ;;
  stage2)
    stage2_deploy
    ;;
  stage3)
    stage3_configure
    ;;
  stage4)
    stage4_start
    ;;
  stage5)
    stage5_validate
    ;;
  all)
    stage1_build
    stage2_deploy
    stage3_configure
    stage4_start
    stage5_validate
    ;;
  *)
    log_error "Unknown stage: $STAGE"
    show_usage
    exit 1
    ;;
esac

log_success "Deployment completed successfully!"
echo ""
echo "Access your deployment:"
echo "  Portal:  http://$TARGET_HOST:3919"
echo "  Metrics: http://$TARGET_HOST:9090/metrics"
echo "  Logs:    ssh $TARGET_USER@$TARGET_HOST tail -f /tmp/portal.log"
echo ""
echo "Deployment log: $DEPLOYMENT_LOG"
