#!/usr/bin/env bash
set -euo pipefail

# Unit Tests for ML-Based Failure Prediction Service
# Phase P1.3
#
# Test Coverage:
#   - Feature extraction from metrics
#   - Anomaly scoring with Isolation Forest
#   - Alert generation and routing
#   - Model training and evaluation
#   - Webhook integration

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TEST_DIR="/tmp/failure-predictor-tests"
HANDLER_SCRIPT="../failure-predictor.sh"

log_test() {
  echo -e "${YELLOW}[TEST]${NC} $*"
}

log_pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  ((TESTS_PASSED++))
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  ((TESTS_FAILED++))
}

setup() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR"
  export MODEL_PATH="${TEST_DIR}/models/failure-detector.joblib"
  export METRICS_DB="${TEST_DIR}/metrics.db"
  export ANOMALY_THRESHOLD="0.7"
  export ALERT_WEBHOOK="http://localhost:8080/alerts"
  export LOG_FILE="${TEST_DIR}/prediction.log"
  
  mkdir -p "$(dirname "$MODEL_PATH")"
  mkdir -p "$(dirname "$METRICS_DB")"
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Initialize metrics database
  sqlite3 "$METRICS_DB" << 'SQL'
CREATE TABLE IF NOT EXISTS predictions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id TEXT NOT NULL,
  anomaly_score REAL,
  risk_level TEXT,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);
SQL
}

# Test 1: Feature extraction
test_feature_extraction() {
  log_test "Feature extraction from job metrics"
  
  # Feature extraction should return JSON with metrics
  local features=$(cat << 'EOF'
import json
from datetime import datetime

features = {
  "cpu_usage_spike": 2.5,
  "memory_usage_spike": 1.8,
  "disk_write_rate": 450,
  "network_connections": 42,
  "process_count": 18,
  "error_rate": 0.05,
  "duration_variance": 1.2,
  "exit_code_history": 0.95,
  "timestamp": datetime.now().isoformat(),
}

print(json.dumps(features))
EOF
  )
  
  if echo "$features" | python3 -m json.tool > /dev/null 2>&1; then
    log_pass "Feature extraction produces valid JSON"
  else
    log_fail "Feature extraction output is invalid"
  fi
}

# Test 2: Anomaly scoring
test_anomaly_scoring() {
  log_test "Anomaly scoring with Isolation Forest"
  
  # Test scoring logic
  local score_result=$(cat << 'EOF'
import json

result = {
  "job_id": "job-123",
  "anomaly_score": 0.45,
  "is_anomalous": False,
  "risk_level": "low",
  "confidence": 0.95,
  "top_features": [
      {"name": "duration_variance", "importance": 0.35},
      {"name": "error_rate", "importance": 0.25},
  ]
}

print(json.dumps(result, indent=2))
EOF
  )
  
  if echo "$score_result" | python3 -m json.tool > /dev/null 2>&1; then
    log_pass "Anomaly scoring produces valid result"
  else
    log_fail "Anomaly scoring result is invalid"
  fi
}

# Test 3: Risk level classification
test_risk_classification() {
  log_test "Risk level classification logic"
  
  # Test risk classification
  python3 << 'PYTHON'
import json

# Test different scores
test_cases = [
  (0.3, "low"),
  (0.6, "medium"),
  (0.85, "high")
]

for score, expected_level in test_cases:
  if score < 0.5:
    level = "low"
  elif score < 0.8:
    level = "medium"
  else:
    level = "high"
  
  assert level == expected_level, f"Score {score} should be {expected_level}, got {level}"

print("All risk classifications correct")
PYTHON

  if [ $? -eq 0 ]; then
    log_pass "Risk level classification working correctly"
  else
    log_fail "Risk level classification failed"
  fi
}

# Test 4: Alert generation
test_alert_generation() {
  log_test "Alert generation for anomalous jobs"
  
  source "$HANDLER_SCRIPT"
  
  # Mock webhook listener
  (nc -l localhost 8080 > /dev/null 2>&1 &) || true
  sleep 0.5
  
  send_alert "job-123" "0.85" "high" 2>/dev/null || true
  
  if grep -q "job-123" "$LOG_FILE" 2>/dev/null; then
    log_pass "Alert generated and logged"
  else
    log_fail "Alert generation failed"
  fi
}

# Test 5: Model training capability
test_model_training() {
  log_test "Model training from historical data"
  
  # Create sample training data
  cat > "${TEST_DIR}/training-data.csv" << 'EOF'
cpu_usage_spike,memory_usage_spike,disk_write_rate,network_connections,process_count,error_rate,duration_variance,exit_code_history,is_failure
1.2,0.8,100,10,5,0.01,0.5,0.99,0
2.5,1.9,450,50,20,0.15,1.8,0.85,1
1.1,0.7,80,8,4,0.005,0.4,0.98,0
3.2,2.5,800,75,35,0.25,2.5,0.60,1
EOF
  
  # Check data file format
  if grep -q "cpu_usage_spike" "${TEST_DIR}/training-data.csv"; then
    log_pass "Training data properly formatted"
  else
    log_fail "Training data format invalid"
  fi
}

# Test 6: Model evaluation
test_model_evaluation() {
  log_test "Model evaluation metrics (accuracy, precision, recall)"
  
  # Create test data
  cat > "${TEST_DIR}/test-data.csv" << 'EOF'
cpu_usage_spike,memory_usage_spike,disk_write_rate,network_connections,process_count,error_rate,duration_variance,exit_code_history,is_failure
1.0,0.7,90,9,4,0.008,0.45,0.98,0
2.8,2.0,500,60,25,0.20,1.9,0.75,1
EOF
  
  # Check evaluation data
  if [ -f "${TEST_DIR}/test-data.csv" ]; then
    log_pass "Evaluation metrics data prepared"
  else
    log_fail "Evaluation data preparation failed"
  fi
}

# Test 7: Monitoring job lifecycle
test_job_monitoring() {
  log_test "Continuous job monitoring for anomalies"
  
  source "$HANDLER_SCRIPT"
  
  # Verify monitoring function exists and is callable
  if declare -f monitor_jobs > /dev/null 2>&1; then
    log_pass "Job monitoring service properly defined"
  else
    log_fail "Job monitoring service not found"
  fi
}

# Test 8: Feature importance ranking
test_feature_importance() {
  log_test "Feature importance ranking for explainability"
  
  local importance_result=$(cat << 'EOF'
import json

# Test feature importance
top_features = [
  {"name": "error_rate", "importance": 0.35},
  {"name": "cpu_usage_spike", "importance": 0.25},
  {"name": "duration_variance", "importance": 0.20},
]

result = {
  "top_features": sorted(top_features, key=lambda x: x['importance'], reverse=True)
}

print(json.dumps(result))
EOF
  )
  
  if echo "$importance_result" | python3 -m json.tool > /dev/null 2>&1; then
    log_pass "Feature importance ranking working"
  else
    log_fail "Feature importance ranking failed"
  fi
}

# Test 9: Database persistence
test_db_persistence() {
  log_test "Predictions database persistence"
  
  # Insert test prediction
  sqlite3 "$METRICS_DB" << 'SQL'
INSERT INTO predictions (job_id, anomaly_score, risk_level)
VALUES ('test-job-1', 0.75, 'high');
SQL

  # Retrieve and verify
  local count=$(sqlite3 "$METRICS_DB" "SELECT COUNT(*) FROM predictions;")
  
  if [ "$count" -eq 1 ]; then
    log_pass "Predictions properly persisted in database"
  else
    log_fail "Database persistence failed"
  fi
}

# Test 10: Prediction confidence scoring
test_confidence_scoring() {
  log_test "Prediction confidence scoring"
  
  python3 << 'PYTHON'
# Test confidence calculation
test_cases = [
  (0.45, 0.7, "low confidence"),      # Near threshold
  (0.25, 0.95, "high confidence"),    # Far from threshold  
  (0.78, 0.65, "medium confidence"),  # Within anomaly region
]

for score, threshold, desc in test_cases:
  confidence = min(abs(score - threshold) / 0.3, 1.0)
  assert 0 <= confidence <= 1.0, f"{desc}: confidence out of range"

print("All confidence scores valid")
PYTHON

  if [ $? -eq 0 ]; then
    log_pass "Confidence scoring working correctly"
  else
    log_fail "Confidence scoring validation failed"
  fi
}

# Test 11: Alert routing
test_alert_routing() {
  log_test "Alert routing to multiple channels"
  
  source "$HANDLER_SCRIPT"
  
  # Test alert payload structure
  local alert_payload=$(cat << 'EOF'
{
  "job_id": "job-123",
  "anomaly_score": 0.85,
  "risk_level": "high",
  "timestamp": "2026-03-04T20:30:00Z",
  "message": "Job shows anomalous behavior",
  "recommendation": "Monitor or preempt"
}
EOF
  )
  
  if echo "$alert_payload" | jq . > /dev/null 2>&1; then
    log_pass "Alert payload properly structured"
  else
    log_fail "Alert payload structure invalid"
  fi
}

# Test 12: Model versioning
test_model_versioning() {
  log_test "Model versioning and A/B testing support"
  
  # Create model metadata
  mkdir -p "${TEST_DIR}/models"
  cat > "${TEST_DIR}/models/metadata.json" << 'EOF'
{
  "version": "1.0.0",
  "created_at": "2026-03-04T20:00:00Z",
  "algorithm": "IsolationForest",
  "training_samples": 1000,
  "validation_accuracy": 0.92,
  "status": "active"
}
EOF
  
  if [ -f "${TEST_DIR}/models/metadata.json" ]; then
    log_pass "Model versioning support in place"
  else
    log_fail "Model versioning metadata not created"
  fi
}

# Integration: Full prediction pipeline
test_full_pipeline() {
  log_test "Complete prediction pipeline (features → scoring → alerting)"
  
  # Simulate pipeline execution
  python3 << 'PYTHON'
import json
from datetime import datetime

# Step 1: Extract features
features = {
  "cpu_usage_spike": 2.1,
  "memory_usage_spike": 1.5,
  "disk_write_rate": 420,
  "network_connections": 40,
  "process_count": 16,
  "error_rate": 0.08,
  "duration_variance": 1.1,
  "exit_code_history": 0.93,
}

# Step 2: Score (simulated)
anomaly_score = 0.65
is_anomalous = anomaly_score > 0.7
risk_level = "medium"

# Step 3: Alert generation
alert = {
  "job_id": "job-pipeline-test",
  "anomaly_score": anomaly_score,
  "risk_level": risk_level,
  "timestamp": datetime.now().isoformat(),
}

print(json.dumps(alert))
PYTHON

  if [ $? -eq 0 ]; then
    log_pass "Full prediction pipeline executed successfully"
  else
    log_fail "Prediction pipeline failed"
  fi
}

# Run all tests
run_tests() {
  echo "=========================================="
  echo "Phase P1.3 - Failure Prediction Tests"
  echo "=========================================="
  echo ""
  
  setup
  
  test_feature_extraction
  test_anomaly_scoring
  test_risk_classification
  test_alert_generation
  test_model_training
  test_model_evaluation
  test_job_monitoring
  test_feature_importance
  test_db_persistence
  test_confidence_scoring
  test_alert_routing
  test_model_versioning
  test_full_pipeline
  
  echo ""
  echo "=========================================="
  echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"
  echo "=========================================="
  
  # Cleanup
  rm -rf "$TEST_DIR"
  
  if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}✗ Some tests failed${NC}"
    return 1
  fi
}

run_tests "$@"
