#!/bin/bash
# Monitoring Stack OAuth2 Verification & Testing
# Comprehensive validation of OAuth2-Proxy, Grafana, Keycloak integration
# Date: 2026-03-14

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
WARN=0

# Functions
print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS++))
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL++))
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN++))
}

print_success() {
    echo -e "${GREEN}✓ SUCCESS:${NC} $1"
}

print_error() {
    echo -e "${RED}✗ ERROR:${NC} $1"
}

test_endpoint() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}
    
    if curl -sf -o /dev/null -w "%{http_code}" "$url" | grep -q "$expected_code"; then
        print_pass "$name endpoint responding ($expected_code)"
        return 0
    else
        print_fail "$name endpoint not responding"
        return 1
    fi
}

test_service_health() {
    local container=$1
    local expected_status=$2
    
    # Check if container is running
    if docker ps --format "table {{.Names}}" | grep -q "^${container}$"; then
        print_pass "Container $container is running"
        return 0
    else
        print_fail "Container $container is NOT running"
        return 1
    fi
}

# Main Script
print_header "🔐 MONITORING STACK OAUTH2 VERIFICATION"

print_section "1. Checking Docker & Docker Compose"

if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
    print_pass "Docker installed ($DOCKER_VERSION)"
else
    print_fail "Docker not found"
    exit 1
fi

if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)
    print_pass "Docker Compose installed ($COMPOSE_VERSION)"
else
    print_fail "Docker Compose not found"
    exit 1
fi

echo ""
print_section "2. Checking Container Status"

# Wait a few seconds for services to stabilize
sleep 3

services=("sso-keycloak-dev" "sso-prometheus-dev" "sso-grafana-dev" "sso-oauth2-proxy-dev" "sso-redis-dev")

for service in "${services[@]}"; do
    test_service_health "$service" || true
done

echo ""
print_section "3. Testing Service Endpoints"

# Test Keycloak
print_warn "Keycloak may still be initializing (typical startup time: 15-30 seconds)"
curl -sf http://localhost:8080/auth &> /dev/null && \
    print_pass "Keycloak endpoint responding" || \
    print_warn "Keycloak still initializing..."

# Test Prometheus
test_endpoint "Prometheus" "http://localhost:9090/-/healthy" "200" || true

# Test Grafana
test_endpoint "Grafana" "http://localhost:3000/api/health" "200" || true

# Test OAuth2-Proxy
test_endpoint "OAuth2-Proxy" "http://localhost:4180/oauth2/auth" "403" || true

# Test Redis
if redis-cli -p 6379 ping &> /dev/null 2>&1; then
    print_pass "Redis responding to PING"
else
    print_warn "Redis not responding (may be initializing)"
fi

echo ""
print_section "4. Verifying Configuration Files"

config_files=(
    "docker-compose.yml"
    "docker/nginx/monitoring-router.conf"
    "docker/grafana/grafana-oauth.ini"
)

for config_file in "${config_files[@]}"; do
    config_path="${PROJECT_ROOT}/${config_file}"
    if [ -f "$config_path" ]; then
        print_pass "Configuration file exists: $config_file"
    else
        print_fail "Configuration file missing: $config_file"
    fi
done

echo ""
print_section "5. Checking OAuth2-Proxy Configuration"

# Check docker-compose for OAuth2 settings
if grep -q "OAUTH2_PROXY_PROVIDER.*oidc" "${PROJECT_ROOT}/docker-compose.yml"; then
    print_pass "OAuth2-Proxy OIDC provider configured"
else
    print_fail "OAuth2-Proxy OIDC provider not configured"
fi

if grep -q "OAUTH2_PROXY_OIDC_ISSUER_URL.*keycloak" "${PROJECT_ROOT}/docker-compose.yml"; then
    print_pass "OAuth2-Proxy Keycloak issuer URL configured"
else
    print_fail "OAuth2-Proxy Keycloak issuer URL not configured"
fi

if grep -q "OAUTH2_PROXY_COOKIE_HTTPONLY.*true" "${PROJECT_ROOT}/docker-compose.yml"; then
    print_pass "OAuth2-Proxy cookie security enabled (HttpOnly)"
else
    print_fail "OAuth2-Proxy cookie security not properly configured"
fi

echo ""
print_section "6. Checking Grafana OAuth Configuration"

if grep -q "GF_AUTH_GENERIC_OAUTH_ENABLED" "${PROJECT_ROOT}/docker-compose.yml"; then
    print_pass "Grafana OAuth authentication enabled"
else
    print_fail "Grafana OAuth authentication not configured"
fi

if grep -q "GF_AUTH_GENERIC_OAUTH_CLIENT_ID.*grafana" "${PROJECT_ROOT}/docker-compose.yml"; then
    print_pass "Grafana OAuth client ID configured"
else
    print_fail "Grafana OAuth client ID not configured"
fi

echo ""
print_section "7. Checking Nginx Router Configuration"

if grep -q "upstream prometheus_backend" "${PROJECT_ROOT}/docker/nginx/monitoring-router.conf"; then
    print_pass "Prometheus upstream configured in Nginx"
else
    print_fail "Prometheus upstream not configured in Nginx"
fi

if grep -q "upstream grafana_backend" "${PROJECT_ROOT}/docker/nginx/monitoring-router.conf"; then
    print_pass "Grafana upstream configured in Nginx"
else
    print_fail "Grafana upstream not configured in Nginx"
fi

if grep -q "X-Frame-Options" "${PROJECT_ROOT}/docker/nginx/monitoring-router.conf"; then
    print_pass "Security headers configured in Nginx"
else
    print_fail "Security headers not configured in Nginx"
fi

echo ""
print_section "8. Checking Documentation"

docs=(
    "MONITORING_OAUTH_ACCESS.md"
    "KEYCLOAK_OAUTH_CLIENT_SETUP.md"
)

for doc in "${docs[@]}"; do
    if [ -f "${PROJECT_ROOT}/${doc}" ]; then
        print_pass "Documentation available: $doc"
    else
        print_fail "Documentation missing: $doc"
    fi
done

echo ""
print_section "9. Checking Setup Scripts"

if [ -f "${PROJECT_ROOT}/scripts/setup-monitoring-oauth.sh" ]; then
    if [ -x "${PROJECT_ROOT}/scripts/setup-monitoring-oauth.sh" ]; then
        print_pass "Setup script exists and is executable"
    else
        print_warn "Setup script exists but not executable"
        chmod +x "${PROJECT_ROOT}/scripts/setup-monitoring-oauth.sh"
        print_pass "Setup script now executable"
    fi
else
    print_fail "Setup script not found"
fi

echo ""
print_section "10. Testing OAuth2 Redirect Flow (Manual)"

echo ""
echo -e "${YELLOW}NOTE:${NC} To fully test OAuth2 authentication:"
echo ""
echo "1. Open browser to secured endpoint:"
echo "   ${CYAN}http://localhost:4180/grafana/${NC}"
echo ""
echo "2. Verify redirect to Keycloak:"
echo "   ${CYAN}http://localhost:8080/auth/realms/master/protocol/openid-connect/auth${NC}"
echo ""
echo "3. Login with default credentials:"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "4. Verify redirect back to Grafana dashboard"
echo ""

echo ""
print_header "📊 VERIFICATION SUMMARY"

echo -e "${CYAN}Tests Passed:  ${GREEN}${PASS}${NC}"
echo -e "${CYAN}Tests Failed:  ${RED}${FAIL}${NC}"
echo -e "${CYAN}Warnings:      ${YELLOW}${WARN}${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
    print_success "All critical tests passed!"
    echo ""
    echo -e "${GREEN}🔐 Monitoring Stack OAuth2 Configuration is READY${NC}"
else
    print_error "Some tests failed. Please check the configuration."
    exit 1
fi

echo ""
print_header "🚀 NEXT STEPS"

echo "1. Setup Keycloak OAuth2 Clients:"
echo "   Read: ${CYAN}KEYCLOAK_OAUTH_CLIENT_SETUP.md${NC}"
echo ""
echo "2. Access Monitoring Stack:"
echo "   Secured URL: ${CYAN}http://localhost:4180/grafana/${NC}"
echo "   Direct: ${CYAN}http://localhost:3000${NC} (development only)"
echo ""
echo "3. Monitor OAuth2-Proxy:"
echo "   Metrics: ${CYAN}http://localhost:8080/metrics${NC}"
echo "   Logs: ${CYAN}docker-compose logs -f oauth2-proxy${NC}"
echo ""
echo "4. Verify Complete Setup:"
echo "   Read: ${CYAN}MONITORING_OAUTH_ACCESS.md${NC}"
echo ""
echo "2. For production, enable TLS:"
echo "   See: ${CYAN}MONITORING_OAUTH_ACCESS.md#production-deployment${NC}"
echo ""

print_header "✅ VERIFICATION COMPLETE"
