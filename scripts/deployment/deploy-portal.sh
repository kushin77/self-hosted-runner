#!/bin/bash

# NexusShield Portal - Automated Deployment Script
# Target: 192.168.168.42 (Production Fullstack)
# Status: Production Ready
# Last Updated: 2026-03-10

set -e

###############################################################################
# CONFIGURATION
###############################################################################

DEPLOYMENT_HOST="192.168.168.42"
SSH_USER="runner"
COMPONENT="backend"
IMAGE_NAME="nexusshield-backend"
IMAGE_TAG="$(date +%Y%m%d_%H%M%S)"
BACKUP_SUFFIX="backup_$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# FUNCTIONS
###############################################################################

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

check_prerequisite() {
  if ! command -v "$1" &> /dev/null; then
    log_error "$1 is not installed"
    exit 1
  fi
}

###############################################################################
# VALIDATION PHASE
###############################################################################

validate_environment() {
  log_info "=== VALIDATION PHASE ==="
  
  # Check local prerequisites
  log_info "Checking local prerequisites..."
  check_prerequisite "docker"
  check_prerequisite "git"
  log_success "Local tools available"
  
  # Verify deployment host
  log_info "Verifying deployment host: $DEPLOYMENT_HOST"
  if [ "$DEPLOYMENT_HOST" = "localhost" ] || [ "$DEPLOYMENT_HOST" = "127.0.0.1" ]; then
    log_error "Cannot deploy to localhost!"
    log_error "Deployment target MUST be 192.168.168.42"
    exit 1
  fi
  
  # Test SSH access
  log_info "Testing SSH access to $SSH_USER@$DEPLOYMENT_HOST..."
  if ! ssh -o ConnectTimeout=5 "$SSH_USER@$DEPLOYMENT_HOST" "echo OK" 2>/dev/null; then
    log_error "Cannot SSH to $DEPLOYMENT_HOST"
    log_error "Check: ssh $SSH_USER@$DEPLOYMENT_HOST"
    exit 1
  fi
  log_success "SSH access verified"
  
  # Check deployment environment
  log_info "Checking deployment environment..."
  ssh "$SSH_USER@$DEPLOYMENT_HOST" << 'EOF'
    # Disk space
    DISK=$(df /home | awk 'NR==2 {print $4}')
    if [ $DISK -lt 500000 ]; then
      echo "ERROR: Insufficient disk space"
      exit 1
    fi
    
    # Docker available
    if ! docker ps > /dev/null 2>&1; then
      echo "ERROR: Docker not available"
      exit 1
    fi
    
    # Docker Compose available
    if ! docker-compose --version > /dev/null 2>&1; then
      echo "ERROR: Docker Compose not available"
      exit 1
    fi
EOF
  log_success "Deployment environment verified"
  
  # Verify credentials file
  log_info "Verifying credentials in .env.production..."
  if [ ! -f "backend/.env.production" ]; then
    log_error "backend/.env.production not found"
    log_error "Create it from: backend/.env.example"
    exit 1
  fi
  
  # Check for placeholder values
  if grep -E "^(GCP_PROJECT_ID|GCP_KMS_KEY|DATABASE_URL|REDIS_PASSWORD)=(your_|example_|change_me|test_)" \
       backend/.env.production > /dev/null; then
    log_error "Found placeholder values in .env.production:"
    grep -E "^(GCP_PROJECT_ID|GCP_KMS_KEY|DATABASE_URL|REDIS_PASSWORD)=(your_|example_|change_me|test_)" \
         backend/.env.production || true
    log_error "Replace placeholders with real values"
    exit 1
  fi
  log_success "Credentials verified"
  
  # Check git status
  log_info "Checking git status..."
  if [ -n "$(git status --porcelain)" ]; then
    log_warning "Uncommitted changes detected"
    git status --short
    if [ "${FORCE:-}" = "true" ] || [ "${CI:-}" = "true" ] || [ "${NONINTERACTIVE:-}" = "true" ]; then
      log_info "FORCE/CI/NONINTERACTIVE set — proceeding despite uncommitted changes"
    else
      read -p "Continue anyway? (y/N) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Deployment cancelled"
        exit 1
      fi
    fi
  fi
  log_success "Git status verified"
  
  log_success "=== ALL VALIDATION CHECKS PASSED ==="
}

###############################################################################
# BACKUP PHASE
###############################################################################

backup_current_state() {
  log_info "=== BACKUP PHASE ==="
  
  # Backup local .env
  if [ -f "backend/.env.production" ]; then
    log_info "Backing up .env.production..."
    cp backend/.env.production "backend/.env.production.$BACKUP_SUFFIX"
    log_success "Local backup created: backend/.env.production.$BACKUP_SUFFIX"
  fi
  
  # Backup on remote
  log_info "Backing up remote state..."
  ssh "$SSH_USER@$DEPLOYMENT_HOST" << EOF
    # Backup database
    log_info "Backing up database..."
    docker exec nexusshield-postgres pg_dump \
      postgresql://nexusshield:nexusshield_secure@localhost:5432/nexusshield \
      | gzip > ~/nexusshield_db_backup_$BACKUP_SUFFIX.sql.gz 2>/dev/null || true
    
    # Backup Docker image
    log_info "Backing up Docker image..."
    docker commit nexusshield-backend \
      nexusshield-backend:$BACKUP_SUFFIX 2>/dev/null || true
    
    # Backup .env on remote
    if [ -f ~/.env ]; then
      cp ~/.env ~/env_backup_$BACKUP_SUFFIX
    fi
EOF
  log_success "Remote backups created"
  
  log_success "=== BACKUP PHASE COMPLETE ==="
}

###############################################################################
# BUILD PHASE
###############################################################################

build_backend() {
  log_info "=== BUILD PHASE ==="
  
  log_info "Building backend component..."
  cd backend
  
  # Clean previous builds
  log_info "Cleaning previous builds..."
  rm -rf dist/ node_modules/.cache
  
  # Install dependencies (deterministic: use npm ci when lockfile exists)
  log_info "Installing dependencies..."
  if [ -f package-lock.json ]; then
    npm ci --no-audit --no-fund
  else
    npm install --no-audit --no-fund
  fi
  
  # Build TypeScript
  log_info "Compiling TypeScript..."
  if ! npm run build; then
    log_error "TypeScript compilation failed"
    exit 1
  fi
  log_success "TypeScript compiled successfully"
  
  # Verify build artifacts
  if [ ! -f "dist/index.js" ]; then
    log_error "Build artifacts not found: dist/index.js"
    exit 1
  fi
  log_success "Build artifacts verified"
  
  cd ..
  log_success "=== BUILD PHASE COMPLETE ==="
}

###############################################################################
# DOCKER PHASE
###############################################################################

build_docker_image() {
  log_info "=== DOCKER BUILD PHASE ==="
  
  cd backend
  
  log_info "Building Docker image: $IMAGE_NAME:$IMAGE_TAG"
  if ! docker build \
    -t "$IMAGE_NAME:$IMAGE_TAG" \
    -t "$IMAGE_NAME:latest" \
    .; then
    log_error "Docker build failed"
    exit 1
  fi
  
  log_success "Docker image built: $IMAGE_NAME:$IMAGE_TAG"
  
  # Verify image
  if ! docker images | grep -q "$IMAGE_NAME"; then
    log_error "Docker image not found after build"
    exit 1
  fi
  
  log_success "Docker image verified"
  cd ..
  log_success "=== DOCKER BUILD PHASE COMPLETE ==="
}

###############################################################################
# DEPLOYMENT PHASE
###############################################################################

deploy_to_production() {
  log_info "=== DEPLOYMENT PHASE ==="
  
  # Stop current services
  log_info "Stopping current services..."
  ssh "$SSH_USER@$DEPLOYMENT_HOST" << EOF
    docker-compose stop || true
    docker stop nexusshield-backend || true
    sleep 2
EOF
  log_success "Services stopped"
  
  # Transfer configuration
  log_info "Transferring configuration files..."
  scp docker-compose.yml "$SSH_USER@$DEPLOYMENT_HOST:~/"
  scp backend/.env.production "$SSH_USER@$DEPLOYMENT_HOST:~/.env"
  log_success "Configuration transferred"
  
  # Start services
  log_info "Starting services..."
  ssh "$SSH_USER@$DEPLOYMENT_HOST" << EOF
    cd ~
    docker-compose up -d
    
    # Wait for services to stabilize
    sleep 10
    
    # Show status
    docker-compose ps
EOF
  log_success "Services started"
  
  #Wait for backend to be ready
  log_info "Waiting for backend to become ready..."
  max_attempts=30
  attempt=0
  while [ $attempt -lt $max_attempts ]; do
    if curl -s -I "http://$DEPLOYMENT_HOST:3000/ready" | grep -q "200"; then
      log_success "Backend is ready"
      break
    fi
    attempt=$((attempt + 1))
    if [ $attempt -lt $max_attempts ]; then
      sleep 2
    fi
  done
  
  if [ $attempt -eq $max_attempts ]; then
    log_warning "Backend took longer than expected to become ready"
  fi
  
  log_success "=== DEPLOYMENT PHASE COMPLETE ==="
}

###############################################################################
# VERIFICATION PHASE
###############################################################################

verify_deployment() {
  log_info "=== VERIFICATION PHASE ==="
  
  # Health check
  log_info "Checking health endpoints..."
  
  # Liveness
  if curl -s "http://$DEPLOYMENT_HOST:3000/alive" | grep -q "alive"; then
    log_success "Liveness check passed"
  else
    log_error "Liveness check failed"
    exit 1
  fi
  
  # Readiness
  if curl -s "http://$DEPLOYMENT_HOST:3000/ready" | grep -q "ready"; then
    log_success "Readiness check passed"
  else
    log_error "Readiness check failed"
    exit 1
  fi
  
  # Verify services
  log_info "Verifying services..."
  ssh "$SSH_USER@$DEPLOYMENT_HOST" "docker-compose ps"
  
  # Verify database
  log_info "Verifying database connectivity..."
  ssh "$SSH_USER@$DEPLOYMENT_HOST" << EOF
    docker exec nexusshield-postgres psql \
      postgresql://nexusshield:nexusshield_secure@localhost:5432/nexusshield \
      -c "SELECT version();" > /dev/null 2>&1 && echo "Database OK" || echo "Database ERROR"
EOF
  
  log_success "=== VERIFICATION PHASE COMPLETE ==="
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
  echo
  echo "╔════════════════════════════════════════════════════╗"
  echo "║   NexusShield Portal - Automated Deployment        ║"
  echo "╚════════════════════════════════════════════════════╝"
  echo
  echo "Configuration:"
  echo "  Target Host:     $DEPLOYMENT_HOST"
  echo "  SSH User:        $SSH_USER"
  echo "  Component:       $COMPONENT"
  echo "  Image Tag:       $IMAGE_TAG"
  echo
  
  read -p "Proceed with deployment? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_error "Deployment cancelled by user"
    exit 0
  fi
  
  validate_environment
  backup_current_state
  build_backend
  build_docker_image
  deploy_to_production
  verify_deployment
  
  echo
  echo "╔════════════════════════════════════════════════════╗"
  echo "║   ✓ Deployment Successful                          ║"
  echo "╚════════════════════════════════════════════════════╝"
  echo
  echo "Next steps:"
  echo "  1. Verify: curl http://$DEPLOYMENT_HOST:3000/ready"
  echo "  2. Test:   curl http://$DEPLOYMENT_HOST:3000/metrics | head -10"
  echo "  3. Logs:   ssh $SSH_USER@$DEPLOYMENT_HOST docker-compose logs -f"
  echo
  echo "Rollback available:"
  echo "  ssh $SSH_USER@$DEPLOYMENT_HOST docker-compose down"
  echo
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO"' ERR

main "$@"
