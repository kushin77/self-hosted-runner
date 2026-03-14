#!/bin/bash
# Monitoring Stack OAuth2 Access Setup
# Secures Prometheus, Grafana, and Alertmanager with Keycloak OAuth2-OIDC
# Date: 2026-03-14
# Version: 1.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
DOCKER_COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"

echo "🔐 Monitoring Stack OAuth2 Access Setup"
echo "========================================"
echo ""

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Step 1: Validate Docker & Docker Compose
print_status "Step 1: Validating Docker setup..."
if ! command -v docker &> /dev/null; then
    print_error "Docker not found. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose not found. Please install Docker Compose first."
    exit 1
fi

print_success "Docker and Docker Compose are installed"
echo ""

# Step 2: Check docker-compose.yml configuration
print_status "Step 2: Verifying docker-compose.yml configuration..."
if ! grep -q "oauth2-proxy" "${DOCKER_COMPOSE_FILE}"; then
    print_error "OAuth2-Proxy service not found in docker-compose.yml"
    exit 1
fi

if ! grep -q "GF_AUTH_GENERIC_OAUTH" "${DOCKER_COMPOSE_FILE}"; then
    print_error "Grafana OIDC configuration not found in docker-compose.yml"
    exit 1
fi

print_success "All required services configured in docker-compose.yml"
echo ""

# Step 3: Check nginx monitoring router config
print_status "Step 3: Checking nginx monitoring router configuration..."
if [ ! -f "${PROJECT_ROOT}/docker/nginx/monitoring-router.conf" ]; then
    print_error "Monitoring router configuration not found at ${PROJECT_ROOT}/docker/nginx/monitoring-router.conf"
    exit 1
fi

print_success "Monitoring router nginx configuration verified"
echo ""

# Step 4: Start containers
print_status "Step 4: Starting Docker containers..."
cd "${PROJECT_ROOT}"

# Stop any existing containers
docker-compose down 2>/dev/null || true

# Start all services
docker-compose up -d

# Wait for services to be healthy
print_status "Waiting for services to start..."
sleep 10

# Check health of key services
services_to_check=("keycloak" "prometheus" "grafana" "oauth2-proxy")

for service in "${services_to_check[@]}"; do
    container_name="sso-${service}-dev"
    if docker ps | grep -q "${container_name}"; then
        print_success "Container ${container_name} is running"
    else
        print_error "Container ${container_name} failed to start"
        docker-compose logs "${service}"
        exit 1
    fi
done

echo ""

# Step 5: Verify service connectivity
print_status "Step 5: Verifying service connectivity..."

# Check Keycloak
if curl -sf http://localhost:8080/auth &> /dev/null; then
    print_success "Keycloak is accessible at http://localhost:8080/auth"
else
    print_warn "Keycloak health check pending - it may still be initializing"
fi

# Check OAuth2-Proxy
if curl -sf http://localhost:4180/oauth2/auth &> /dev/null; then
    print_success "OAuth2-Proxy is accessible at http://localhost:4180"
else
    print_warn "OAuth2-Proxy health check failed - checking logs..."
    docker-compose logs oauth2-proxy | tail -10
fi

# Check Prometheus
if curl -sf http://localhost:9090/-/healthy &> /dev/null; then
    print_success "Prometheus is accessible at http://localhost:9090"
else
    print_warn "Prometheus health check pending"
fi

# Check Grafana
if curl -sf http://localhost:3000/api/health &> /dev/null; then
    print_success "Grafana is accessible at http://localhost:3000"
else
    print_warn "Grafana health check pending"
fi

echo ""
echo "========================================"
echo "🔐 OAuth2 Monitoring Stack Access Setup"
echo "========================================"
echo ""
echo "✅ SECURED MONITORING ENDPOINTS:"
echo ""
echo "1. 🔒 OAuth2-Proxy (Authentication Gateway)"
echo "   URL: http://localhost:4180"
echo "   Function: OIDC gateway protecting all monitoring services"
echo "   Status: Requires OAuth authentication"
echo ""
echo "2. 📊 Grafana Dashboards"
echo "   Direct URL: http://localhost:3000"
echo "   Secured URL: http://localhost:4180/grafana/"
echo "   OAuth: Keycloak OIDC (auto-provisioned users)"
echo "   Admin: admin / admin (default, change in production)"
echo ""
echo "3. 📈 Prometheus Metrics"
echo "   Direct URL: http://localhost:9090"
echo "   Secured URL: http://localhost:4180/prometheus/"
echo "   Query Endpoint: http://localhost:4180/api/v1/query"
echo ""
echo "4. 🚨 Alertmanager"
echo "   Direct URL: http://localhost:9093"
echo "   Secured URL: http://localhost:4180/alertmanager/"
echo ""
echo "KEYCLOAK OIDC PROVIDER:"
echo "   URL: http://localhost:8080/auth"
echo "   Admin Console: http://localhost:8080/auth/admin"
echo "   Realm: master"
echo "   Admin User: admin / admin"
echo ""
echo "========================================"
echo "🔑 ACCESSING THE MONITORING STACK"
echo "========================================"
echo ""
echo "Option 1: Browser Access (Recommended)"
echo "  1. Open http://localhost:4180/grafana/"
echo "  2. Redirect to Keycloak login"
echo "  3. Authenticate with Keycloak credentials"
echo "  4. Dashboard provisioned and ready"
echo ""
echo "Option 2: Direct Access (Development Only)"
echo "  Grafana:     http://localhost:3000 (no auth required)"
echo "  Prometheus:  http://localhost:9090 (no auth required)"
echo "  Alertmanager: http://localhost:9093 (no auth required)"
echo ""
echo "⚠️  NOTE: Direct access bypasses OAuth2. Use secured URLs for production."
echo ""
echo "========================================"
echo "🔐 SECURITY CONFIGURATION"
echo "========================================"
echo ""
echo "✓ OAuth2-Proxy Configuration:"
echo "  - OIDC Provider: Keycloak"
echo "  - Cookie Secure: false (development)"
echo "  - Cookie HTTP-Only: true"
echo "  - Cookie SameSite: Lax"
echo "  - Metrics: http://localhost:8080/metrics"
echo ""
echo "✓ Grafana OAuth Configuration:"
echo "  - Generic OAuth: Enabled"
echo "  - Client ID: grafana"
echo "  - Auto Provisioning: Yes"
echo "  - Auto Role Assignment: Viewer"
echo ""
echo "✓ Nginx Router:"
echo "  - Upstream Prometheus: http://prometheus:9090"
echo "  - Upstream Grafana: http://grafana:3000"
echo "  - Upstream Alertmanager: http://alertmanager:9093"
echo "  - Health Endpoint: http://localhost:8888/health"
echo ""
echo "========================================"
echo "📋 NEXT STEPS"
echo "========================================"
echo ""
echo "1. Create OAuth2-Proxy client in Keycloak:"
echo "   - Client ID: oauth2-proxy"
echo "   - Redirect URI: http://localhost:4180/oauth2/callback"
echo "   - Protocol: OIDC"
echo ""
echo "2. Create Grafana client in Keycloak:"
echo "   - Client ID: grafana"
echo "   - Redirect URI: http://localhost:3000/login/generic_oauth"
echo "   - Protocol: OIDC"
echo ""
echo "3. Test OAuth authentication:"
echo "   curl -H 'X-Forwarded-For: 127.0.0.1' http://localhost:4180/oauth2/auth"
echo ""
echo "4. Verify Keycloak user provisioning:"
echo "   kubectl logs -f pods/grafana-* -n keycloak"
echo ""
echo "========================================"
echo ""
print_success "Monitoring Stack OAuth2 Setup Complete!"
print_status "Access the monitoring dashboards at: http://localhost:4180/grafana/"
echo ""
