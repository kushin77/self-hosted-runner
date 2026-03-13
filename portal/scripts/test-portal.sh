#!/bin/bash
# NexusShield Portal Testing Script
# Runs comprehensive integration tests to verify the deployment

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

# Test tracking
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

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

log_test_result() {
    local test_name=$1
    local test_result=$2
    local test_details=$3
    
    if [ $test_result -eq 0 ]; then
        TEST_RESULTS+=("$test_name: ✅ PASS")
        ((TESTS_PASSED++))
    else
        TEST_RESULTS+=("$test_name: ❌ FAIL - $test_details")
        ((TESTS_FAILED++))
    fi
}

# ===== HEALTH CHECK TESTS =====

test_backend_health() {
    log_info "Testing Backend Health Check..."
    local response=$(curl -s -w "\n%{http_code}" http://localhost:5000/health)
    local body=$(echo "$response" | head -n -1)
    local http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "200" ]; then
        log_success "Backend health check passed"
        log_test_result "Backend Health" 0
        return 0
    else
        log_error "Backend health check failed with status $http_code"
        log_test_result "Backend Health" 1 "HTTP $http_code"
        return 1
    fi
}

test_frontend_health() {
    log_info "Testing Frontend Accessibility..."
    local response=$(curl -s -w "\n%{http_code}" http://localhost:3000)
    local http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "200" ]; then
        log_success "Frontend is accessible"
        log_test_result "Frontend Accessibility" 0
        return 0
    else
        log_error "Frontend check failed with status $http_code"
        log_test_result "Frontend Accessibility" 1 "HTTP $http_code"
        return 1
    fi
}

# ===== API ENDPOINT TESTS =====

test_api_health() {
    log_info "Testing API /health endpoint..."
    local response=$(curl -s -w "\n%{http_code}" http://localhost:5000/health)
    local http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "200" ]; then
        log_success "API /health endpoint working"
        log_test_result "API /health" 0
        return 0
    else
        log_error "API /health failed with status $http_code"
        log_test_result "API /health" 1 "HTTP $http_code"
        return 1
    fi
}

test_api_credentials() {
    log_info "Testing API /api/v1/credentials endpoint..."
    local response=$(curl -s -w "\n%{http_code}" http://localhost:5000/api/v1/credentials 2>/dev/null)
    local http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "401" ]; then
        log_success "API /api/v1/credentials endpoint responding"
        log_test_result "API /api/v1/credentials" 0
        return 0
    else
        log_warning "API /api/v1/credentials returned $http_code"
        log_test_result "API /api/v1/credentials" 1 "HTTP $http_code"
        return 1
    fi
}

test_api_metrics() {
    log_info "Testing API /metrics endpoint..."
    local response=$(curl -s -w "\n%{http_code}" http://localhost:5000/metrics 2>/dev/null)
    local http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "404" ]; then
        log_success "API /metrics endpoint responding (or not configured)"
        log_test_result "API /metrics" 0
        return 0
    else
        log_warning "API /metrics returned $http_code"
        log_test_result "API /metrics" 1 "HTTP $http_code"
        return 1
    fi
}

# ===== SERVICE VERIFICATION TESTS =====

test_services_running() {
    log_info "Checking if all required services are running..."
    cd "$DOCKER_DIR"
    
    local api_status=$(docker-compose ps portal-api 2>/dev/null | grep -c "Up\|running" || echo "0")
    local frontend_status=$(docker-compose ps portal-frontend 2>/dev/null | grep -c "Up\|running" || echo "0")
    
    if [ "$api_status" -gt 0 ] && [ "$frontend_status" -gt 0 ]; then
        log_success "All services are running"
        log_test_result "Services Running" 0
        return 0
    else
        log_error "Not all services are running (API: $api_status, Frontend: $frontend_status)"
        log_test_result "Services Running" 1 "API: $api_status, Frontend: $frontend_status"
        return 1
    fi
}

test_docker_containers() {
    log_info "Verifying Docker container health..."
    cd "$DOCKER_DIR"
    
    local unhealthy=$(docker-compose ps 2>/dev/null | grep -i "unhealthy\|exited" | wc -l || echo "0")
    
    if [ "$unhealthy" -eq 0 ]; then
        log_success "All containers are healthy"
        log_test_result "Docker Container Health" 0
        return 0
    else
        log_warning "Found $unhealthy unhealthy containers"
        docker-compose ps
        log_test_result "Docker Container Health" 1 "$unhealthy unhealthy containers"
        return 1
    fi
}

# ===== CONNECTIVITY TESTS =====

test_api_responds() {
    log_info "Testing API responsiveness..."
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if curl -s -m 5 http://localhost:5000/health > /dev/null 2>&1; then
            log_success "API is responsive"
            log_test_result "API Responsiveness" 0
            return 0
        fi
        retry=$((retry + 1))
        sleep 1
    done
    
    log_error "API is not responding after $max_retries attempts"
    log_test_result "API Responsiveness" 1 "No response after $max_retries retries"
    return 1
}

test_frontend_responds() {
    log_info "Testing Frontend responsiveness..."
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if curl -s -m 5 http://localhost:3000 > /dev/null 2>&1; then
            log_success "Frontend is responsive"
            log_test_result "Frontend Responsiveness" 0
            return 0
        fi
        retry=$((retry + 1))
        sleep 1
    done
    
    log_error "Frontend is not responding after $max_retries attempts"
    log_test_result "Frontend Responsiveness" 1 "No response after $max_retries retries"
    return 1
}

# ===== MAIN TEST RUNNER =====

run_all_tests() {
    log_info "Starting Portal Integration Tests..."
    echo ""
    
    # Service verification
    test_services_running || true
    test_docker_containers || true
    
    # Health checks
    test_backend_health || true
    test_frontend_health || true
    
    # API endpoint tests
    test_api_health || true
    test_api_credentials || true
    test_api_metrics || true
    
    # Connectivity tests
    test_api_responds || true
    test_frontend_responds || true
    
    echo ""
    log_info "Test Results Summary"
    echo "═══════════════════════════════════════════════════════════════"
    for result in "${TEST_RESULTS[@]}"; do
        echo "  $result"
    done
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All tests passed! ✨"
        return 0
    else
        log_warning "$TESTS_FAILED test(s) failed"
        return 1
    fi
}

# ===== EXECUTION =====

cd "$PORTAL_DIR"

log_info "NexusShield Portal Testing Suite"
echo ""

run_all_tests
TEST_EXIT_CODE=$?

echo ""
echo "Useful Commands:"
echo "  View logs:       docker-compose -f docker/docker-compose.yml logs -f"
echo "  Backend logs:    docker-compose -f docker/docker-compose.yml logs -f portal-api"
echo "  Frontend logs:   docker-compose -f docker/docker-compose.yml logs -f portal-frontend"
echo "  Restart:         docker-compose -f docker/docker-compose.yml restart"
echo "  Stop:            docker-compose -f docker/docker-compose.yml down"
echo ""

exit $TEST_EXIT_CODE
