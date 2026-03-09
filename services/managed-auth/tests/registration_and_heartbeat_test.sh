#!/bin/bash
# Integration tests for Managed-Auth API (Runner registration and heartbeat)

set -e

BASE_URL="${BASE_URL:-http://localhost:8080}"
API_PREFIX="/api/v1"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Logging functions
log_info() {
  echo -e "${YELLOW}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
  ((TESTS_PASSED++))
}

log_error() {
  echo -e "${RED}[✗]${NC} $1"
  ((TESTS_FAILED++))
}

# Helper function for HTTP requests
make_request() {
  local method=$1
  local endpoint=$2
  local data=$3
  local token=$4
  
  local headers="-H Content-Type:application/json"
  if [ -n "$token" ]; then
    headers="$headers -H Authorization:Bearer\ $token"
  fi
  
  if [ -n "$data" ]; then
    curl -s -X "$method" "$BASE_URL$endpoint" $headers -d "$data"
  else
    curl -s -X "$method" "$BASE_URL$endpoint" $headers
  fi
}

# Test function wrapper
run_test() {
  local name=$1
  local test_func=$2
  
  echo ""
  echo "Running: $name"
  ((TESTS_RUN++))
  
  if $test_func; then
    log_success "$name"
  else
    log_error "$name"
  fi
}

# ===== TEST CASES =====

# Test 1: Health check
test_health_check() {
  local response=$(curl -s "$BASE_URL/health")
  echo "Response: $response"
  
  if echo "$response" | grep -q "ok"; then
    return 0
  fi
  return 1
}

# Test 2: Create access token
test_create_token() {
  local token_request='{
    "ttl_seconds": 3600,
    "job_type": "ci-build",
    "resource_tags": {"team": "platform"}
  }'
  
  local response=$(make_request POST "$API_PREFIX/auth/token" "$token_request")
  echo "Response: $response"
  
  # Check that response contains access_token
  if echo "$response" | grep -q "access_token"; then
    # Extract and store the token for later use
    ACCESS_TOKEN=$(echo "$response" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    echo "Token: $ACCESS_TOKEN"
    return 0
  fi
  return 1
}

# Test 3: Register runner
test_register_runner() {
  if [ -z "$ACCESS_TOKEN" ]; then
    log_error "No access token available"
    return 1
  fi
  
  local register_request='{
    "name": "runner-linux-01",
    "os": "ubuntu-latest",
    "arch": "x86_64",
    "labels": ["docker", "linux", "self-hosted"],
    "pool": "default",
    "vpc_id": "vpc-12345",
    "region": "us-east-1",
    "max_jobs": 4
  }'
  
  local response=$(make_request POST "$API_PREFIX/runners/register" "$register_request" "$ACCESS_TOKEN")
  echo "Response: $response"
  
  # Check for runner_id in response
  if echo "$response" | grep -q "runner_id"; then
    # Extract and store the runner ID
    RUNNER_ID=$(echo "$response" | grep -o '"runner_id":"[^"]*' | cut -d'"' -f4 | head -1)
    echo "Runner ID: $RUNNER_ID"
    return 0
  fi
  return 1
}

# Test 4: Get runner status
test_get_runner_status() {
  if [ -z "$RUNNER_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
    log_error "No runner ID or access token available"
    return 1
  fi
  
  local response=$(make_request GET "$API_PREFIX/runners/$RUNNER_ID" "" "$ACCESS_TOKEN")
  echo "Response: $response"
  
  if echo "$response" | grep -q "running\|provisioning"; then
    return 0
  fi
  return 1
}

# Test 5: Send heartbeat
test_send_heartbeat() {
  if [ -z "$RUNNER_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
    log_error "No runner ID or access token available"
    return 1
  fi
  
  local heartbeat_request='{
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "status": "idle",
    "current_job_id": null,
    "job_history": [],
    "metrics": {
      "cpu_percent": 15.5,
      "memory_percent": 32.2,
      "disk_percent": 18.9
    },
    "system_info": {
      "load_average": [0.5, 0.6, 0.4],
      "uptime": 86400,
      "process_count": 45
    }
  }'
  
  local response=$(make_request POST "$API_PREFIX/runners/$RUNNER_ID/heartbeat" "$heartbeat_request" "$ACCESS_TOKEN")
  echo "Response: $response"
  
  if echo "$response" | grep -q "heartbeat_received"; then
    return 0
  fi
  return 1
}

# Test 6: Send periodic heartbeats (simulating continuous connection)
test_multiple_heartbeats() {
  if [ -z "$RUNNER_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
    log_error "No runner ID or access token available"
    return 1
  fi
  
  local count=0
  for i in {1..3}; do
    local heartbeat_request='{
      "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "status": "idle",
      "metrics": {"cpu_percent": '$((10 + RANDOM % 40))', "memory_percent": '$((20 + RANDOM % 60))', "disk_percent": 15}
    }'
    
    local response=$(make_request POST "$API_PREFIX/runners/$RUNNER_ID/heartbeat" "$heartbeat_request" "$ACCESS_TOKEN")
    
    if echo "$response" | grep -q "heartbeat_received"; then
      ((count++))
    fi
    
    sleep 1
  done
  
  if [ $count -eq 3 ]; then
    echo "Successfully sent $count heartbeats"
    return 0
  fi
  return 1
}

# Test 7: Send healthcheck
test_send_healthcheck() {
  if [ -z "$RUNNER_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
    log_error "No runner ID or access token available"
    return 1
  fi
  
  local healthcheck_request='{
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "health": {
      "docker_socket": true,
      "disk_available_gb": 150,
      "network_connectivity": true,
      "vault_connectivity": true
    }
  }'
  
  local response=$(make_request POST "$API_PREFIX/runners/$RUNNER_ID/healthcheck" "$healthcheck_request" "$ACCESS_TOKEN")
  echo "Response: $response"
  
  if echo "$response" | grep -q "health_status"; then
    return 0
  fi
  return 1
}

# Test 8: Heartbeat with active job
test_heartbeat_with_job() {
  if [ -z "$RUNNER_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
    log_error "No runner ID or access token available"
    return 1
  fi
  
  local heartbeat_request='{
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "status": "running",
    "current_job_id": "job-12345",
    "job_history": [
      {
        "id": "job-12344",
        "status": "completed",
        "duration": 45,
        "result": "success"
      }
    ],
    "metrics": {"cpu_percent": 85, "memory_percent": 72, "disk_percent": 28}
  }'
  
  local response=$(make_request POST "$API_PREFIX/runners/$RUNNER_ID/heartbeat" "$heartbeat_request" "$ACCESS_TOKEN")
  echo "Response: $response"
  
  if echo "$response" | grep -q "heartbeat_received"; then
    return 0
  fi
  return 1
}

# Test 9: Register second runner
test_register_second_runner() {
  if [ -z "$ACCESS_TOKEN" ]; then
    log_error "No access token available"
    return 1
  fi
  
  local register_request='{
    "name": "runner-linux-02",
    "os": "ubuntu-latest",
    "arch": "x86_64",
    "pool": "default"
  }'
  
  local response=$(make_request POST "$API_PREFIX/runners/register" "$register_request" "$ACCESS_TOKEN")
  echo "Response: $response"
  
  if echo "$response" | grep -q "runner_id"; then
    RUNNER_ID_2=$(echo "$response" | grep -o '"runner_id":"[^"]*' | cut -d'"' -f4 | head -1)
    echo "Runner 2 ID: $RUNNER_ID_2"
    return 0
  fi
  return 1
}

# Test 10: Get audit logs
test_get_audit_logs() {
  if [ -z "$ACCESS_TOKEN" ]; then
    log_error "No access token available"
    return 1
  fi
  
  local response=$(make_request GET "$API_PREFIX/audit/logs" "" "$ACCESS_TOKEN")
  echo "Response: $response"
  
  if echo "$response" | grep -q "logs"; then
    return 0
  fi
  return 1
}

# Test 11: Deregister runner (graceful shutdown)
test_deregister_runner() {
  if [ -z "$RUNNER_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
    log_error "No runner ID or access token available"
    return 1
  fi
  
  local deregister_request='{
    "reason": "scheduled_maintenance",
    "drain_timeout": 60
  }'
  
  local response=$(make_request DELETE "$API_PREFIX/runners/$RUNNER_ID" "$deregister_request" "$ACCESS_TOKEN")
  echo "Response: $response"
  
  if echo "$response" | grep -q "draining\|drained"; then
    return 0
  fi
  return 1
}

# Test 12: Verify runner is draining
test_verify_runner_draining() {
  if [ -z "$RUNNER_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
    log_error "No runner ID or access token available"
    return 1
  fi
  
  sleep 1
  
  local response=$(make_request GET "$API_PREFIX/runners/$RUNNER_ID" "" "$ACCESS_TOKEN")
  echo "Response: $response"
  
  if echo "$response" | grep -q "draining"; then
    return 0
  fi
  return 1
}

# ===== MAIN EXECUTION =====

echo "========================================="
echo "Managed-Auth API Integration Tests"
echo "Base URL: $BASE_URL"
echo "========================================="

# Wait for service to be ready
echo -n "Waiting for service to be ready..."
for i in {1..30}; do
  if curl -s "$BASE_URL/health" > /dev/null 2>&1; then
    echo " OK"
    break
  fi
  if [ $i -eq 30 ]; then
    echo " TIMEOUT"
    exit 1
  fi
  echo -n "."
  sleep 1
done

# Run all tests
run_test "Health check" test_health_check
run_test "Create access token" test_create_token
run_test "Register runner" test_register_runner
run_test "Get runner status" test_get_runner_status
run_test "Send heartbeat" test_send_heartbeat
run_test "Send multiple heartbeats" test_multiple_heartbeats
run_test "Send healthcheck" test_send_healthcheck
run_test "Heartbeat with active job" test_heartbeat_with_job
run_test "Register second runner" test_register_second_runner
run_test "Get audit logs" test_get_audit_logs
run_test "Deregister runner (graceful shutdown)" test_deregister_runner
run_test "Verify runner is draining" test_verify_runner_draining

# Print summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Tests Run: $TESTS_RUN"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed!${NC}"
  exit 1
fi
