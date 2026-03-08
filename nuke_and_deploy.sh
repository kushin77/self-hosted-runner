#!/bin/bash
# 🔥 COMPLETE NUKE & FRESH DEPLOY - FULL STACK VERSION
# Run this on a machine with Docker access
# Usage: bash nuke_and_deploy.sh

set -euo pipefail

WORKSPACE="${1:-.}"
cd "$WORKSPACE"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔥 COMPLETE ENVIRONMENT NUKE - FRESH DEPLOY 0-100"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Working directory: $WORKSPACE"
echo ""

# =============================================================================
# PHASE 1: DOCKER SERVICES SHUTDOWN
# =============================================================================
echo "📍 PHASE 1: STOPPING ALL DOCKER SERVICES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "⏹️  Stopping docker-compose stack..."
docker-compose down -v 2>/dev/null || true
docker-compose -f docker-compose.dev.yml down -v 2>/dev/null || true

echo "🔪 Force removing all containers..."
docker ps -aq | xargs -r docker kill 2>/dev/null || true
docker ps -aq | xargs -r docker rm -f 2>/dev/null || true

echo "🧹 Pruning volumes..."
docker volume prune -af 2>/dev/null || true

sleep 3

# =============================================================================
# PHASE 2: LOCAL ARTIFACTS & STATE CLEANUP
# =============================================================================
echo ""
echo "📍 PHASE 2: CLEANING LOCAL ARTIFACTS & STATE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Build artifacts
echo "🗑️  Removing build artifacts..."
rm -rf build dist .next coverage .rollup.cache .tsc-out .rollup 2>/dev/null || true
rm -rf .cache node_modules/.cache 2>/dev/null || true

# State files
echo "🗑️  Removing state files..."
rm -f .bootstrap-state.json .ops-blocker-state.json 2>/dev/null || true
rm -f plan.txt plan-post-import.txt dry-run-report.json 2>/dev/null || true
rm -f portal-artifact.json multi-registry-push-results.json 2>/dev/null || true
rm -f .continuous_blocker_monitor.pid 2>/dev/null || true

# Logs
echo "🗑️  Clearing logs..."
rm -rf logs/* 2>/dev/null || true
rm -f *.log 2>/dev/null || true

# Caches
echo "🗑️  Clearing caches..."
find . -type d -name .cache -exec rm -rf {} + 2>/dev/null || true
find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

# Test artifacts
echo "🗑️  Removing test artifacts..."
rm -rf coverage test_results.txt .nyc_output 2>/dev/null || true
rm -rf .chaos-test-results artifacts-run-* 2>/dev/null || true

# =============================================================================
# PHASE 3: TERRAFORM STATE RESET
# =============================================================================
echo ""
echo "📍 PHASE 3: RESETTING TERRAFORM STATE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -d "terraform" ]; then
    echo "🗑️  Removing Terraform working directory..."
    rm -rf terraform/.terraform 2>/dev/null || true
    rm -f terraform/.terraform.lock.hcl 2>/dev/null || true
    rm -f terraform/terraform.tfstate* 2>/dev/null || true
    
    echo "✅ Terraform state cleared"
fi

# =============================================================================
# PHASE 4: DOCKER IMAGE CLEANUP
# =============================================================================
echo ""
echo "📍 PHASE 4: CLEANING DOCKER IMAGES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "🧹 Removing dangling images and building cache..."
docker image prune -af 2>/dev/null || true
docker builder prune -af 2>/dev/null || true

echo "✅ Docker cache cleaned"

# =============================================================================
# PHASE 5: FRESH DEPENDENCIES
# =============================================================================
echo ""
echo "📍 PHASE 5: INSTALLING FRESH DEPENDENCIES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Node.js
if [ -f "package.json" ]; then
    echo "📦 Installing Node dependencies..."
    rm -rf node_modules package-lock.json 2>/dev/null || true
    npm install --prefer-offline --audit=false --loglevel=error 2>&1 | grep -E "added|up to date|ERR" || true
    echo "✅ Node dependencies installed"
fi

# Python
if [ -f "requirements.txt" ]; then
    echo "🐍 Setting up Python environment..."
    rm -rf .venv 2>/dev/null || true
    python3 -m venv .venv >/dev/null 2>&1
    source .venv/bin/activate
    pip install -qq --upgrade pip >/dev/null 2>&1
    pip install -qq -r requirements.txt >/dev/null 2>&1 || true
    echo "✅ Python environment ready"
fi

# =============================================================================
# PHASE 6: DOCKER BUILD & START (FRESH)
# =============================================================================
echo ""
echo "📍 PHASE 6: FRESH DOCKER BUILD & DEPLOYMENT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "📥 Pulling latest base images..."
docker pull vault:1.15.0 2>&1 | tail -3 || true
docker pull redis:7.2-alpine 2>&1 | tail -3 || true
docker pull postgres:15-alpine 2>&1 | tail -3 || true
docker pull minio/minio:latest 2>&1 | tail -3 || true

echo ""
echo "🔨 Building fresh containers..."
docker-compose -f docker-compose.dev.yml build --no-cache --progress plain 2>&1 | tail -50 || true

echo ""
echo "🚀 Starting services..."
docker-compose -f docker-compose.dev.yml up -d 2>&1 | tail -20

sleep 10

# =============================================================================
# PHASE 7: HEALTH CHECK & STATUS
# =============================================================================
echo ""
echo "📍 PHASE 7: HEALTH CHECK & SERVICE STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "🏥 Service Status:"
docker-compose -f docker-compose.dev.yml ps

echo ""
echo "🧪 Testing service connectivity..."
echo ""

# Test each service
FAILED=0

# Vault
if curl -s http://localhost:8200/v1/sys/health >/dev/null 2>&1; then
    echo "✅ Vault (8200) - READY"
else
    echo "❌ Vault (8200) - NOT RESPONDING"
    FAILED=$((FAILED+1))
fi

# Redis
if redis-cli ping >/dev/null 2>&1; then
    echo "✅ Redis (6379) - READY"
else
    echo "❌ Redis (6379) - NOT RESPONDING"
    FAILED=$((FAILED+1))
fi

# PostgreSQL
if PGPASSWORD=runner_password psql -h localhost -U runner_user -d runner_db -c "SELECT 1" >/dev/null 2>&1; then
    echo "✅ PostgreSQL (5432) - READY"
else
    echo "❌ PostgreSQL (5432) - NOT RESPONDING"
    FAILED=$((FAILED+1))
fi

# MinIO
if curl -s http://localhost:9000/minio/health/live >/dev/null 2>&1; then
    echo "✅ MinIO (9000/9001) - READY"
else
    echo "❌ MinIO (9000/9001) - NOT RESPONDING"
    FAILED=$((FAILED+1))
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ FRESH DEPLOYMENT COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $FAILED -eq 0 ]; then
    echo "✅ ALL SYSTEMS OPERATIONAL"
else
    echo "⚠️  $FAILED service(s) need investigation"
fi

echo ""
echo "📍 SERVICE ENDPOINTS:"
echo ""
echo "  🔐 Vault Auth"
echo "     URL: http://localhost:8200"
echo "     Token: dev-token-12345"
echo ""
echo "  📦 Redis"
echo "     Host: localhost:6379"
echo "     Command: redis-cli -h localhost"
echo ""
echo "  🗄️  PostgreSQL"
echo "     Host: localhost:5432"
echo "     User: runner_user"
echo "     Password: runner_password"
echo "     DB: runner_db"
echo ""
echo "  🪣 MinIO S3 Storage"
echo "     API: http://localhost:9000"
echo "     Console: http://localhost:9001"
echo "     User: minioadmin"
echo "     Password: minioadmin123"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 Environment ready for testing 0-100"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit $FAILED
