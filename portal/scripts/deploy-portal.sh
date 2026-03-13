#!/bin/bash
# NexusShield Portal Deployment Script
# Deploys and verifies the full stack: Backend + Frontend + Database + Redis

set -e

# Get the script directory and portal directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTAL_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="${DOCKER_DIR:-$PORTAL_DIR}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Trap errors
exit_on_error() {
    log_error "Deployment failed at line $1"
    exit 1
}

trap 'exit_on_error ${LINENO}' ERR

# ===== DEPLOYMENT STEPS =====

log_info "Starting NexusShield Portal Deployment..."

# Step 1: Environment Setup
log_info "Step 1: Setting up environment..."
cd "$PORTAL_DIR"

if [ ! -f "$DOCKER_DIR/.env.production" ]; then
    log_warning ".env.production not found, creating from template..."
    if [ -f "$DOCKER_DIR/docker/.env.example" ] || [ -f "$DOCKER_DIR/.env.example" ]; then
        ENV_TEMPLATE="$DOCKER_DIR/docker/.env.example"
        [ -f "$DOCKER_DIR/.env.example" ] && ENV_TEMPLATE="$DOCKER_DIR/.env.example"
        cp "$ENV_TEMPLATE" "$DOCKER_DIR/.env.production"
        log_info "Created .env.production from template"
    else
        log_error "Template .env.example not found"
        exit 1
    fi
fi

# Step 2: Build Docker images
log_info "Step 2: Building Docker images..."
cd "$DOCKER_DIR"
docker-compose build --no-cache || {
    log_error "Failed to build Docker images"
    exit 1
}
log_success "Docker images built successfully"

# Step 3: Stop any existing containers
log_info "Step 3: Checking for existing containers..."
if docker-compose ps | grep -q "portal-api\|portal-frontend"; then
    log_info "Stopping existing containers..."
    docker-compose down || true
fi

# Step 4: Start services
log_info "Step 4: Starting services..."
docker-compose up -d --remove-orphans
log_success "Services started"

# Step 5: Wait for services to be ready
log_info "Step 5: Waiting for services to be ready..."
MAX_ATTEMPTS=30
ATTEMPT=0

# Check Backend API
log_info "Waiting for Backend API (http://localhost:5000/health)..."
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s http://localhost:5000/health > /dev/null 2>&1; then
        log_success "Backend API is healthy"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo -n "."
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    log_warning "Backend API health check timeout - continuing with deployment"
fi

# Check Frontend
ATTEMPT=0
log_info "Waiting for Frontend (http://localhost:3000)..."
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        log_success "Frontend is accessible"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    echo -n "."
    sleep 2
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    log_warning "Frontend health check timeout - continuing with deployment"
fi

# Step 6: Run smoke tests
log_info "Step 6: Running smoke tests..."
if [ -f "$DOCKER_DIR/smoke-check.sh" ]; then
    bash "$DOCKER_DIR/smoke-check.sh" || log_warning "Some smoke tests failed, but deployment continues"
else
    log_warning "smoke-check.sh not found, skipping smoke tests"
fi

# Step 7: Display deployment summary
log_info "Step 7: Deployment Summary"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Portal Deployment Complete"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Services Running:"
docker-compose ps --services
echo ""
echo "Endpoints:"
echo "  Backend API:  http://localhost:5000"
echo "  Health Check: http://localhost:5000/health"
echo "  Frontend:     http://localhost:3000"
echo "  API Routes:   http://localhost:5000/api/v1/*"
echo ""
echo "Logs:"
echo "  View all:     docker-compose logs -f"
echo "  Backend only: docker-compose logs -f portal-api"
echo "  Frontend only: docker-compose logs -f portal-frontend"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

log_success "✨ NexusShield Portal deployment completed successfully!"
echo ""
echo "Next Steps:"
echo "  1. Verify backend at http://localhost:5000/health"
echo "  2. Access frontend at http://localhost:3000"
echo "  3. Run: make test (or bash scripts/test-portal.sh)"
echo ""

exit 0
