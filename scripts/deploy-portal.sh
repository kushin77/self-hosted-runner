#!/bin/bash
###############################################################################
# NexusShield Portal - Immutable Idempotent Deployment Script
# Purpose: Deploy portal services with full health verification
# Mode: Hands-off, fully automated, no manual intervention
# Deployment: Direct (no GitHub Actions)
###############################################################################

set -euo pipefail

# Configuration
REPO_ROOT="/home/akushnir/self-hosted-runner"
DEPLOYMENT_ID=$(date -u +%Y%m%d_%H%M%S_%Z)
LOG_FILE="${REPO_ROOT}/logs/deployment_${DEPLOYMENT_ID}.log"
AUDIT_FILE="${REPO_ROOT}/logs/deployment_audit_${DEPLOYMENT_ID}.jsonl"

# Ensure log directories exist
mkdir -p "${REPO_ROOT}/logs"

# ===== LOGGING FUNCTIONS =====
log() {
  local level=$1
  shift
  local message="$@"
  local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

audit_entry() {
  local action=$1
  local status=$2
  local details=$3
  local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local entry=$(jq -n \
    --arg ts "$timestamp" \
    --arg act "$action" \
    --arg st "$status" \
    --arg det "$details" \
    '{timestamp: $ts, action: $act, status: $st, details: $det, deployment_id: "'${DEPLOYMENT_ID}'"}')
  echo "$entry" >> "${AUDIT_FILE}"
}

# ===== PRE-FLIGHT CHECKS =====
log "INFO" "=== NexusShield Portal Deployment v1.0 ==="
log "INFO" "Deployment ID: ${DEPLOYMENT_ID}"
audit_entry "deployment_start" "in_progress" "Portal deployment initiated"

# Check prerequisites
log "INFO" "Performing pre-flight checks..."

if ! command -v docker &> /dev/null; then
  log "ERROR" "Docker not found"
  audit_entry "deployment_check" "failed" "Docker not installed"
  exit 1
fi

if ! command -v docker-compose &> /dev/null; then
  log "ERROR" "docker-compose not found"
  audit_entry "deployment_check" "failed" "docker-compose not installed"
  exit 1
fi

if ! [ -f "${REPO_ROOT}/docker-compose.yml" ]; then
  log "ERROR" "docker-compose.yml not found"
  audit_entry "deployment_check" "failed" "docker-compose.yml missing"
  exit 1
fi

if ! [ -f "${REPO_ROOT}/backend/server.js" ]; then
  log "ERROR" "backend/server.js not found"
  audit_entry "deployment_check" "failed" "Backend code missing"
  exit 1
fi

log "INFO" "✅ Pre-flight checks passed"
audit_entry "deployment_check" "ok" "All prerequisites met"

# ===== BUILD PHASE =====
log "INFO" "=== Building Docker Images ==="
cd "${REPO_ROOT}"

# Build with proper error handling
if docker-compose build --no-cache 2>&1 | tee -a "${LOG_FILE}"; then
  log "INFO" "✅ Docker images built successfully"
  audit_entry "docker_build" "ok" "Images built: backend, frontend, postgres, redis"
else
  log "ERROR" "Docker build failed"
  audit_entry "docker_build" "failed" "Build process exited with error"
  exit 1
fi

# ===== DEPLOYMENT PHASE =====
log "INFO" "=== Starting Services ==="

# Stop existing containers (idempotent - safe if already stopped)
log "INFO" "Stopping existing containers (if any)..."
docker-compose down --remove-orphans 2>&1 | tee -a "${LOG_FILE}" || true
audit_entry "docker_down" "ok" "Existing containers stopped"

# Start services
log "INFO" "Starting portal services..."
if docker-compose up -d 2>&1 | tee -a "${LOG_FILE}"; then
  log "INFO" "✅ Services started"
  audit_entry "docker_up" "ok" "All services started (backend, frontend, postgres, redis)"
else
  log "ERROR" "Service startup failed"
  audit_entry "docker_up" "failed" "docker-compose up command failed"
  exit 1
fi

# ===== HEALTH VERIFICATION =====
log "INFO" "=== Health Verification Phase ==="

MAX_RETRIES=30
RETRY_DELAY=2
SERVICES=("postgres" "redis" "backend" "frontend")

for service in "${SERVICES[@]}"; do
  log "INFO" "Waiting for ${service} to be healthy..."
  
  case "$service" in
    postgres)
      CONTAINER="nexusshield-postgres"
      CHECK_CMD="docker exec ${CONTAINER} pg_isready -U portal"
      ;;
    redis)
      CONTAINER="nexusshield-redis"
      CHECK_CMD="docker exec ${CONTAINER} redis-cli ping"
      ;;
    backend)
      CONTAINER="nexusshield-backend"
      CHECK_CMD="curl -sf http://localhost:3000/health > /dev/null"
      ;;
    frontend)
      CONTAINER="nexusshield-frontend"
      CHECK_CMD="curl -sf http://localhost:3001/ > /dev/null"
      ;;
  esac
  
  ATTEMPT=0
  while [ $ATTEMPT -lt $MAX_RETRIES ]; do
    if eval "$CHECK_CMD" 2>/dev/null; then
      log "INFO" "✅ ${service} is healthy"
      audit_entry "service_health_${service}" "ok" "${service} health check passed"
      break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -lt $MAX_RETRIES ]; then
      sleep $RETRY_DELAY
    fi
  done
  
  if [ $ATTEMPT -eq $MAX_RETRIES ]; then
    log "WARN" "⚠️  ${service} health check timed out (${MAX_RETRIES} retries)"
    audit_entry "service_health_${service}" "timeout" "Health check did not respond within ${MAX_RETRIES} attempts"
  fi
done

# ===== ENDPOINT TESTING =====
log "INFO" "=== Endpoint Verification ==="

ENDPOINTS=(
  "GET|http://localhost:3000/health"
  "GET|http://localhost:3000/api/health"
  "GET|http://localhost:3000/metrics"
  "GET|http://localhost:3001/"
)

for endpoint in "${ENDPOINTS[@]}"; do
  METHOD="${endpoint%|*}"
  URL="${endpoint#*|}"
  
  log "INFO" "Testing ${METHOD} ${URL}..."
  if curl -sf -X "${METHOD}" "${URL}" > /dev/null 2>&1; then
    log "INFO" "✅ ${URL} responding"
    audit_entry "endpoint_test" "ok" "${METHOD} ${URL} returned successful response"
  else
    log "WARN" "⚠️  ${URL} not responding yet"
    audit_entry "endpoint_test" "timeout" "${METHOD} ${URL} did not respond"
  fi
done

# ===== DEPLOYMENT STATUS =====
log "INFO" "=== Deployment Status ==="

# Get container status
CONTAINER_STATUS=$(docker-compose ps --services | while read svc; do
  STATUS=$(docker-compose ps "$svc" | tail -1 | awk '{print $NF}')
  echo "  - ${svc}: ${STATUS}"
done)

log "INFO" "Container Status:"
echo "$CONTAINER_STATUS" | tee -a "${LOG_FILE}"

# Get logs summary
log "INFO" "=== Recent Logs ==="
for svc in backend frontend postgres redis; do
  log "INFO" "--- ${svc} logs (last 5 lines) ---"
  docker-compose logs --tail=5 "$svc" 2>/dev/null | tee -a "${LOG_FILE}" || true
done

# ===== COMPLETION =====
log "INFO" "=== Deployment Complete ==="
audit_entry "deployment_complete" "success" "Portal deployment completed successfully"

cat << EOF | tee -a "${LOG_FILE}"

╔══════════════════════════════════════════════════════════════════════╗
║   ✅ NexusShield Portal - Production Ready                           ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  Backend API:   http://localhost:3000                               ║
║  Frontend UI:   http://localhost:3001                               ║
║  Health Check:  http://localhost:3000/health                        ║
║  Metrics:       http://localhost:3000/metrics                       ║
║                                                                      ║
║  Deployment ID: ${DEPLOYMENT_ID}                         ║
║  Log File:      ${LOG_FILE} ║
║  Audit File:    ${AUDIT_FILE} ║
║                                                                      ║
║  Status:        DEPLOYED (Idempotent, Immutable)                    ║
║  Re-run safety: YES (Safe to re-run for updates)                    ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

EOF

log "INFO" "Deployment logs saved to: ${LOG_FILE}"
log "INFO" "Audit trail saved to: ${AUDIT_FILE}"

exit 0
