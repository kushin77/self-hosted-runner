#!/bin/bash
# Phase 6: Quick Start - One-Command Execution
# Prerequisite: Docker, Docker Compose, .env file prepared

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Phase 6: Portal MVP Integration - Quick Start             ║"
echo "║  Status: READY FOR EXECUTION                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PHASE="6"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
AUDIT_LOG="logs/phase6-quickstart-${TIMESTAMP:0:10}.jsonl"

mkdir -p logs

# Step 1: Verify Prerequisites
echo -e "${BLUE}Step 1: Verifying Prerequisites${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    VERSION=$("$1" --version 2>/dev/null | head -1 || echo "unknown")
    echo -e "${GREEN}✓${NC} $1 installed ($VERSION)"
    return 0
  else
    echo -e "${RED}✗${NC} $1 NOT found - please install"
    return 1
  fi
}

MISSING=0
check_command "docker" || MISSING=$((MISSING+1))
check_command "docker-compose" || MISSING=$((MISSING+1))
check_command "node" || MISSING=$((MISSING+1))
check_command "python3" || MISSING=$((MISSING+1))

if [ "$MISSING" -gt 0 ]; then
  echo -e "${RED}✗ Missing $MISSING required tools${NC}"
  exit 1
fi

echo ""

# Step 2: Check .env file
echo -e "${BLUE}Step 2: Checking Environment Variables${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -f ".env" ]; then
  echo -e "${RED}✗ .env file not found${NC}"
  echo "Create with: cp .env.example .env && nano .env"
  exit 1
else
  echo -e "${GREEN}✓${NC} .env file found"
  export $(cat .env | xargs)
fi

echo ""

# Step 3: Build Docker Images
echo -e "${BLUE}Step 3: Building Docker Images${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Fetch secrets from secret manager (GSM / Vault) if helper exists
if [ -x "scripts/fetch-secrets.sh" ]; then
  echo "[quickstart] Running scripts/fetch-secrets.sh to populate credentials from GSM/Vault"
  bash scripts/fetch-secrets.sh || echo "[quickstart] fetch-secrets returned non-zero (continuing with env values)"
fi


BUILD_START=$(date +%s)
docker-compose -f docker-compose.phase6.yml build --no-cache 2>&1 | \
  tee -a "$AUDIT_LOG"

BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

echo -e "${GREEN}✓${NC} Build complete (${BUILD_TIME}s)"
echo ""

# Step 4: Start Containers
echo -e "${BLUE}Step 4: Starting Services${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

START_TIME=$(date +%s)
docker-compose -f docker-compose.phase6.yml up -d

echo -e "${GREEN}✓${NC} Containers started"
echo "  Waiting for health checks..."

# Wait for services to be ready
sleep 10

# Count running containers
RUNNING=$(docker ps --filter "label=com.docker.compose.project" --format "{{.Names}}" | wc -l)
echo -e "${GREEN}✓${NC} $RUNNING containers running"

echo ""

# Step 5: Database Initialization
echo -e "${BLUE}Step 5: Initializing Database${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Wait for database to be ready
echo "  Waiting for PostgreSQL..."
for i in {1..30}; do
  if docker-compose -f docker-compose.phase6.yml exec database \
    pg_isready -U portal_user -d portal_db >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} PostgreSQL ready"
    break
  fi
  echo -n "."
  sleep 1
done

echo ""

# Step 6: Verify Integration
echo -e "${BLUE}Step 6: Verifying Integration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Run integration verification script
bash scripts/phase6-integration-verify.sh 2>&1 | tee -a "$AUDIT_LOG"

echo ""

# Step 7: Run Health Checks
echo -e "${BLUE}Step 7: Running Health Checks${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

bash scripts/phase6-health-check.sh 2>&1 | tee -a "$AUDIT_LOG"

echo ""

# Step 8: Summary
echo -e "${BLUE}Step 8: Phase 6 Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FINISH_TIME=$(date +%s)
TOTAL_TIME=$((FINISH_TIME - START_TIME))

echo ""
echo -e "${GREEN}✓ Phase 6 Deployment Complete!${NC}"
echo ""
echo "Deployments Ready at:"
echo "  Frontend:     ${BLUE}http://localhost:3000${NC}"
echo "  API Backend:  ${BLUE}http://localhost:8080${NC}"
echo "  Prometheus:   ${BLUE}http://localhost:9090${NC}"
echo "  Grafana:      ${BLUE}http://localhost:3001${NC}"
echo "  Loki:         ${BLUE}http://localhost:3100${NC}"
echo "  Jaeger:       ${BLUE}http://localhost:16686${NC}"
echo ""
echo "Information:"
echo "  Total time: ${TOTAL_TIME}s"
echo "  Audit log: $AUDIT_LOG"
echo ""
echo "Next Steps:"
echo "  1. Run tests:    pytest backend/tests/integration/ -v"
echo "  2. View logs:    docker-compose logs -f"
echo "  3. Health check: bash scripts/phase6-health-check.sh"
echo ""

echo "{\"timestamp\":\"${TIMESTAMP}\",\"phase\":\"$PHASE\",\"action\":\"quickstart_complete\",\"status\":\"success\",\"total_duration_seconds\":$TOTAL_TIME}" | tee -a "$AUDIT_LOG"
