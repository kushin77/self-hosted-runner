#!/bin/bash

################################################################################
# Local Full Stack Deployment
#
# Starts all components locally with proper port bindings:
#   - Portal UI (React/Vite build or dev) on port 3919
#   - Provisioner-worker (Node.js) with metrics on 9090
#   - Managed-auth backend
#   - All services interconnected and functional
#
# Usage:
#   ./start-full-stack.sh [--mode dev|prod] [--backend-only]
#
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
MODE="${MODE:-prod}"
BACKEND_ONLY="${BACKEND_ONLY:-false}"
DEPLOYMENT_LOG="/tmp/full-stack-local-$(date +%s).log"
PID_FILE="/tmp/fullstack.pids"

# Cleanup on exit
cleanup() {
  echo ""
  echo "Cleaning up..."
  # Kill all background processes
  if [[ -f "$PID_FILE" ]]; then
    while read -r pid; do
      kill "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi
  echo "Deployment stopped"
}

trap cleanup EXIT

# Logging
log_info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }
log_error() { echo -e "${RED}[✗]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$DEPLOYMENT_LOG"; }

# Port availability check
check_port() {
  local port=$1
  if nc -z localhost "$port" 2>/dev/null; then
    log_error "Port $port is already in use"
    return 1
  fi
  return 0
}

################################################################################
# Start Backend Services
################################################################################

start_backend() {
  log_info "Starting backend services..."

  # Provisioner-worker
  log_info "Starting provisioner-worker on metrics port 9090..."
  cd "$REPO_ROOT/services/provisioner-worker"
  ENABLE_METRICS=true METRICS_PORT=9090 node worker.js > "$REPO_ROOT/logs/provisioner-worker.log" 2>&1 &
  local pw_pid=$!
  echo "$pw_pid" >> "$PID_FILE"
  log_success "Provisioner-worker started (PID: $pw_pid)"

  # Managed-auth (entrypoint index.js)
  if [[ -f "$REPO_ROOT/services/managed-auth/index.js" ]]; then
    log_info "Starting managed-auth..."
    cd "$REPO_ROOT/services/managed-auth"
    PORT=4000 node index.js > "$REPO_ROOT/logs/managed-auth.log" 2>&1 &
    local auth_pid=$!
    echo "$auth_pid" >> "$PID_FILE"
    log_success "Managed-auth started (PID: $auth_pid)"
  fi

  sleep 2
  log_success "Backend services started"
}

################################################################################
# Start Portal
################################################################################

start_portal() {
  log_info "Starting portal UI on port 3919..."

  if [[ "$MODE" == "dev" ]]; then
    log_info "Using development mode (npm run dev)..."
    cd "$REPO_ROOT/ElevatedIQ-Mono-Repo/apps/portal"
    PORT=3919 npm run dev > "$REPO_ROOT/logs/portal-dev.log" 2>&1 &
    local portal_pid=$!
  else
    log_info "Using production mode (built dist)..."
    cd "$REPO_ROOT/ElevatedIQ-Mono-Repo/apps/portal"
    
    # Check if dist exists, build if not
    if [[ ! -d "dist" ]]; then
      log_warn "Portal dist not found, building..."
      npm run build > /dev/null 2>&1
    fi

    # Serve with http-server
    if ! command -v http-server &> /dev/null; then
      log_info "Installing http-server..."
      npm install -g http-server > /dev/null 2>&1
    fi

    http-server -a 0.0.0.0 -p 3919 -c-1 dist > "$REPO_ROOT/logs/portal-prod.log" 2>&1 &
    local portal_pid=$!
  fi

  echo "$portal_pid" >> "$PID_FILE"
  log_success "Portal started (PID: $portal_pid, Mode: $MODE)"

  sleep 3
}

################################################################################
# Validation
################################################################################

validate_deployment() {
  log_info "Validating deployment..."

  # Check portal
  log_info "Checking portal on http://localhost:3919..."
  if curl -I http://localhost:3919 2>/dev/null | head -1 | grep -q "200\|301"; then
    log_success "✓ Portal responding on http://localhost:3919"
  else
    log_error "✗ Portal not responding"
  fi

  # Check provisioner-worker metrics
  log_info "Checking provisioner-worker metrics on http://localhost:9090..."
  if curl -I http://localhost:9090/metrics 2>/dev/null | head -1 | grep -q "200"; then
    log_success "✓ Metrics available on http://localhost:9090/metrics"
  else
    log_warn "⚠ Metrics endpoint not responding yet"
  fi

  # List processes
  log_info "Running services:"
  ps aux | grep -E "node|http-server|npm" | grep -v grep | sed 's/^/  /'

  log_success "Validation complete"
}

################################################################################
# Usage
################################################################################

show_usage() {
  cat << EOF
${BLUE}Local Full Stack Deployment${NC}

Usage: $0 [OPTIONS]

Options:
  --mode MODE         Development or production (default: prod)
  --backend-only      Start only backend services (skip portal)
  --help              Show this message

Modes:
  dev                 Use \`npm run dev\` for portal (live reload, slow)
  prod                Use built dist with http-server (faster)

Examples:
  # Production deployment (recommended)
  $0

  # Development mode with live reload
  $0 --mode dev

  # Backend services only
  $0 --backend-only

EOF
}

################################################################################
# Main
################################################################################

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --backend-only)
      BACKEND_ONLY=true
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

# Ensure logs directory exists
mkdir -p "$REPO_ROOT/logs"

log_info "===== Full Stack Local Deployment ====="
log_info "Mode: $MODE"
log_info "Backend only: $BACKEND_ONLY"
log_info "Log file: $DEPLOYMENT_LOG"

# Check ports
log_info "Checking port availability..."
check_port 3919 || { log_error "Cannot use port 3919"; exit 1; }
check_port 9090 || { log_error "Cannot use port 9090"; exit 1; }

# Initialize PID file
> "$PID_FILE"

# Start services
start_backend

if [[ "$BACKEND_ONLY" != "true" ]]; then
  start_portal
fi

# Validate
sleep 3
validate_deployment

# Success message
cat << EOF

${GREEN}✓ Full Stack Deployment Started Successfully!${NC}

Access your deployment:
  ${BLUE}Portal:${NC}        http://localhost:3919
  ${BLUE}Metrics:${NC}       http://localhost:9090/metrics
  ${BLUE}Health:${NC}        http://localhost:9090/health

Logs:
  ${BLUE}Portal:${NC}        tail -f $REPO_ROOT/logs/portal-prod.log
  ${BLUE}Worker:${NC}        tail -f $REPO_ROOT/logs/provisioner-worker.log
  ${BLUE}Auth:${NC}          tail -f $REPO_ROOT/logs/managed-auth.log

To retrieve test data:
  ${BLUE}Provisioning jobs:${NC}
  curl http://localhost:9090/health | jq .metrics.jobs

Press Ctrl+C to stop all services

${DEPLOYMENT_LOG}

EOF

# Keep script running
wait
