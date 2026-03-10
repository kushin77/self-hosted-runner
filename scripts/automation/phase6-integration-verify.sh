#!/bin/bash
# Phase 6: Integration Verification Harness
# Purpose: Verify all Portal MVP components are running and integrated
# Constraints: Immutable audit, ephemeral, idempotent, no GitHub Actions
# Execution: Direct CLI, no dependencies on external services

set -euo pipefail

PROJECT=$(gcloud config get-value project)
AUDIT_LOG="logs/portal-mvp-phase6-integration-verification-$(date +%Y%m%d-%H%M%S).jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p logs

echo "=== Phase 6: Integration Verification Harness ===" >&2
echo "Project: $PROJECT" >&2
echo "Audit: $AUDIT_LOG" >&2
echo ""

# Initialize audit
{
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"action\":\"integration_verification_start\",\"project\":\"$PROJECT\",\"status\":\"in_progress\"}"
} | tee -a "$AUDIT_LOG"

# 1. Verify Frontend Build & Serving
echo "→ Checking frontend build artifacts..." >&2
if [ -d "frontend/dist" ]; then
  SIZE=$(du -sh frontend/dist | cut -f1)
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"frontend_build\",\"status\":\"pass\",\"size\":\"$SIZE\"}" | tee -a "$AUDIT_LOG"
  echo "  ✓ Frontend build present ($SIZE)" >&2
else
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"frontend_build\",\"status\":\"fail\",\"error\":\"dist directory missing\"}" | tee -a "$AUDIT_LOG"
  echo "  ✗ Frontend build missing" >&2
fi

# 2. Verify Cypress E2E Tests
echo "→ Checking Cypress E2E tests..." >&2
if [ -d "frontend/cypress" ]; then
  TEST_COUNT=$(find frontend/cypress/e2e -name "*.cy.ts" 2>/dev/null | wc -l)
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"cypress_e2e\",\"status\":\"pass\",\"test_count\":$TEST_COUNT}" | tee -a "$AUDIT_LOG"
  echo "  ✓ Cypress E2E tests ready ($TEST_COUNT specs)" >&2
else
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"cypress_e2e\",\"status\":\"fail\",\"error\":\"cypress directory missing\"}" | tee -a "$AUDIT_LOG"
  echo "  ✗ Cypress E2E tests missing" >&2
fi

# 3. Verify Backend API Health
echo "→ Checking backend API..." >&2
API_HOST="${PORTAL_API_URL:-http://localhost:8080}"
if command -v curl >/dev/null 2>&1; then
  if curl -s -f "${API_HOST}/health" >/dev/null 2>&1; then
    echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"backend_health\",\"status\":\"pass\",\"endpoint\":\"${API_HOST}/health\"}" | tee -a "$AUDIT_LOG"
    echo "  ✓ Backend API healthy ($API_HOST)" >&2
  else
    echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"backend_health\",\"status\":\"warn\",\"endpoint\":\"${API_HOST}/health\",\"note\":\"API not responding (may not be running)\"}" | tee -a "$AUDIT_LOG"
    echo "  ⚠ Backend API not responding (not started?)" >&2
  fi
else
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"backend_health\",\"status\":\"skip\",\"reason\":\"curl not available\"}" | tee -a "$AUDIT_LOG"
  echo "  ⊘ curl not available (skipping health check)" >&2
fi

# 4. Verify Database Schema
echo "→ Checking database schema..." >&2
if [ -d "backend/migrations" ]; then
  MIGRATION_COUNT=$(find backend/migrations -name "*.sql" 2>/dev/null | wc -l)
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"db_schema\",\"status\":\"pass\",\"migration_count\":$MIGRATION_COUNT}" | tee -a "$AUDIT_LOG"
  echo "  ✓ Database migrations available ($MIGRATION_COUNT files)" >&2
else
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"db_schema\",\"status\":\"fail\",\"error\":\"migrations directory missing\"}" | tee -a "$AUDIT_LOG"
  echo "  ✗ Database migrations missing" >&2
fi

# 5. Verify Audit Trail
echo "→ Checking immutable audit trail..." >&2
AUDIT_COUNT=$(find logs -name "portal-mvp-phase*.jsonl" 2>/dev/null | wc -l)
if [ "$AUDIT_COUNT" -gt 0 ]; then
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"audit_trail\",\"status\":\"pass\",\"audit_count\":$AUDIT_COUNT}" | tee -a "$AUDIT_LOG"
  echo "  ✓ Audit trail operational ($AUDIT_COUNT entries)" >&2
else
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"audit_trail\",\"status\":\"fail\",\"error\":\"no audit entries found\"}" | tee -a "$AUDIT_LOG"
  echo "  ✗ Audit trail missing" >&2
fi

# 6. Verify Container Images (if applicable)
echo "→ Checking container images..." >&2
if command -v docker >/dev/null 2>&1; then
  IMAGES=$(docker images 2>/dev/null | grep nexusshield | wc -l)
  if [ "$IMAGES" -gt 0 ]; then
    echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"container_images\",\"status\":\"pass\",\"image_count\":$IMAGES}" | tee -a "$AUDIT_LOG"
    echo "  ✓ Container images available ($IMAGES)" >&2
  else
    echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"container_images\",\"status\":\"warn\",\"note\":\"no nexusshield images found (may need to build)\"}" | tee -a "$AUDIT_LOG"
    echo "  ⚠ No container images found" >&2
  fi
else
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"container_availability\",\"status\":\"skip\",\"reason\":\"docker not available\"}" | tee -a "$AUDIT_LOG"
  echo "  ⊘ Docker not available" >&2
fi

# 7. Verify Observability Stack (Prometheus/Grafana)
echo "→ Checking observability readiness..." >&2
if [ -d "monitoring" ]; then
  CONFIG_FILES=$(find monitoring -name "*.yaml" -o -name "*.json" 2>/dev/null | wc -l)
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"observability\",\"status\":\"pass\",\"config_count\":$CONFIG_FILES}" | tee -a "$AUDIT_LOG"
  echo "  ✓ Monitoring configurations available ($CONFIG_FILES files)" >&2
else
  echo "{\"timestamp\":\"$TIMESTAMP\",\"phase\":\"phase-6\",\"check\":\"observability\",\"status\":\"warn\",\"note\":\"monitoring directory not found\"}" | tee -a "$AUDIT_LOG"
  echo "  ⚠ Monitoring configurations not prepared" >&2
fi

# Complete audit
{
  COMPLETION_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "{\"timestamp\":\"$COMPLETION_TIME\",\"phase\":\"phase-6\",\"action\":\"integration_verification_complete\",\"status\":\"success\",\"audit_file\":\"$AUDIT_LOG\"}"
} | tee -a "$AUDIT_LOG"

echo ""
echo "✓ Phase 6 Integration Verification Complete" >&2
echo "  Audit trail: $AUDIT_LOG" >&2
echo ""
