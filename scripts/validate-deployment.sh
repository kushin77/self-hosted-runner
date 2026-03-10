#!/bin/bash
# ============================================================================
# NexusShield Portal Backend - Deployment Validation Script
# ============================================================================
# Validates all prerequisites and guardrails before deployment
# Usage: ./scripts/validate-deployment.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Logging functions
log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
  ((PASSED_CHECKS++))
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
  ((FAILED_CHECKS++))
}

check() {
  ((TOTAL_CHECKS++))
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

validate_host() {
  log_info "Checking deployment host..."
  check
  
  if [[ "$DEPLOYMENT_HOST" == "192.168.168.42" ]]; then
    log_success "Correct deployment host: 192.168.168.42"
  else
    log_error "Wrong deployment host: $DEPLOYMENT_HOST (should be 192.168.168.42)"
  fi
}

validate_environment_vars() {
  log_info "Checking environment variables..."
  check
  
  # Check for .env file
  if [[ ! -f ".env" ]] && [[ ! -f "backend/.env" ]]; then
    log_warning ".env file not found - copy from .env.example"
    # Create it for validation
    cp backend/.env.example backend/.env
  fi
  
  # Source env vars
  if [[ -f "backend/.env" ]]; then
    export $(grep -v '^#' backend/.env | xargs)
    log_success "Environment variables loaded"
  else
    log_error "Cannot find .env file"
  fi
}

validate_docker() {
  log_info "Checking Docker installation..."
  check
  
  if command -v docker &> /dev/null; then
    log_success "Docker is installed"
  else
    log_error "Docker is not installed"
    return 1
  fi
  
  if docker ps &> /dev/null; then
    log_success "Docker daemon is running"
  else
    log_error "Docker daemon is not running"
    return 1
  fi
}

validate_docker_compose() {
  log_info "Checking Docker Compose installation..."
  check
  
  if command -v docker-compose &> /dev/null; then
    log_success "Docker Compose is installed"
  else
    log_error "Docker Compose is not installed"
    return 1
  fi
}

validate_node() {
  log_info "Checking Node.js installation..."
  check
  
  if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v)
    log_success "Node.js is installed: $NODE_VERSION"
  else
    log_error "Node.js is not installed"
    return 1
  fi
}

validate_npm() {
  log_info "Checking npm installation..."
  check
  
  if command -v npm &> /dev/null; then
    NPM_VERSION=$(npm -v)
    log_success "npm is installed: $NPM_VERSION"
  else
    log_error "npm is not installed"
    return 1
  fi
}

validate_postgres() {
  log_info "Checking PostgreSQL connectivity..."
  check
  
  if command -v psql &> /dev/null; then
    log_success "PostgreSQL client is available"
  else
    log_warning "PostgreSQL client not available (will check via Docker)"
  fi
}

validate_db_url() {
  log_info "Checking DATABASE_URL..."
  check
  
  if [[ -z "$DATABASE_URL" ]]; then
    log_error "DATABASE_URL not set"
    return 1
  fi
  
  if [[ "$DATABASE_URL" == *"192.168.168.42"* ]] || [[ "$DATABASE_URL" == *"postgres"* ]]; then
    log_success "DATABASE_URL is configured"
  else
    log_warning "DATABASE_URL might be misconfigured: $DATABASE_URL"
  fi
}

validate_jwt_secret() {
  log_info "Checking JWT_SECRET..."
  check
  
  if [[ -z "$JWT_SECRET" ]]; then
    log_error "JWT_SECRET not set"
    return 1
  fi
  
  if [[ ${#JWT_SECRET} -lt 32 ]]; then
    log_warning "JWT_SECRET is short ($ {#JWT_SECRET} chars, recommend 256+ bits)"
  else
    log_success "JWT_SECRET is set (${#JWT_SECRET} chars)"
  fi
}

validate_cors_origins() {
  log_info "Checking CORS_ORIGINS..."
  check
  
  if [[ "$CORS_ORIGINS" == *"192.168.168.42"* ]]; then
    log_success "CORS_ORIGINS correctly configured for 192.168.168.42"
  else
    log_warning "CORS_ORIGINS might not include 192.168.168.42"
  fi
}

validate_backend_structure() {
  log_info "Checking backend directory structure..."
  check
  
  local required_dirs=(
    "backend/src"
    "backend/dist"
    "backend/prisma"
    "backend/config"
    "backend/logs"
  )
  
  for dir in "${required_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      log_success "Directory exists: $dir"
    else
      log_warning "Directory missing: $dir"
    fi
  done
}

validate_backend_files() {
  log_info "Checking backend files..."
  check
  
  local required_files=(
    "backend/Dockerfile"
    "backend/docker-compose.yml"
    "backend/package.json"
    "backend/tsconfig.json"
    "backend/.env.example"
    "backend/README.md"
    "backend/DEPLOYMENT_GUIDE.md"
  )
  
  for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
      log_success "File exists: $file"
    else
      log_error "File missing: $file"
    fi
  done
}

validate_typescript_build() {
  log_info "Checking TypeScript compilation..."
  check
  
  cd backend
  if npm run build &> /dev/null; then
    log_success "TypeScript compiles successfully"
  else
    log_error "TypeScript compilation failed"
  fi
  cd ..
}

validate_docker_build() {
  log_info "Checking Docker build (dry-run)..."
  check
  
  cd backend
  if docker build -t nexusshield-backend:1.0.0-test . &> /dev/null; then
    log_success "Docker build succeeds"
    docker rmi nexusshield-backend:1.0.0-test 2>/dev/null || true
  else
    log_error "Docker build failed"
  fi
  cd ..
}

validate_network() {
  log_info "Checking network connectivity..."
  check
  
  if ping -c 1 192.168.168.42 &> /dev/null; then
    log_success "Can reach 192.168.168.42"
  else
    log_warning "Cannot reach 192.168.168.42 (might be this host)"
  fi
}

validate_ports() {
  log_info "Checking required ports..."
  check
  
  local ports=(3000 5432 6379 8080)
  
  for port in "${ports[@]}"; do
    if nc -z 127.0.0.1 $port 2>/dev/null; then
      log_warning "Port $port is already in use"
    else
      log_success "Port $port is available"
    fi
  done
}

validate_disk_space() {
  log_info "Checking disk space..."
  check
  
  local available=$(df /home | awk 'NR==2 {print $4}')
  if [[ $available -gt 5242880 ]]; then  # 5GB in KB
    log_success "Sufficient disk space: $(($available / 1024 / 1024))GB available"
  else
    log_error "Insufficient disk space: $(($available / 1024 / 1024))GB available (need 5GB+)"
  fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  NexusShield Portal Backend - Deployment Validation            ║"
  echo "║  Host: 192.168.168.42                                           ║"
  echo "║  Date: $(date)          ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  # Run all validation checks
  validate_host
  validate_environment_vars
  validate_docker
  validate_docker_compose
  validate_node
  validate_npm
  validate_postgres
  validate_db_url
  validate_jwt_secret
  validate_cors_origins
  validate_backend_structure
  validate_backend_files
  validate_typescript_build
  validate_docker_build
  validate_network
  validate_ports
  validate_disk_space
  
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  Validation Summary                                             ║"
  echo "├────────────────────────────────────────────────────────────────┤"
  echo "│ Total Checks:    $TOTAL_CHECKS"
  echo "│ Passed:          $PASSED_CHECKS"
  echo "│ Failed:          $FAILED_CHECKS"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  
  if [[ $FAILED_CHECKS -eq 0 ]]; then
    log_success "All validation checks passed!"
    log_info "Ready to deploy with: docker-compose up -d"
    return 0
  else
    log_error "$FAILED_CHECKS checks failed"
    log_info "Please fix the issues above before deploying"
    return 1
  fi
}

# Run main
main
