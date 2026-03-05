#!/usr/bin/env bash
set -euo pipefail

# ML-Based Failure Prediction Service (Phase P1)
# Analyzes running jobs for anomalies and predicts failures
#
# Features:
#   - Real-time feature extraction from job metrics
#   - Isolation Forest anomaly scoring
#   - Historical pattern comparison
#   - Proactive alerts and recommendations

MODEL_PATH="${MODEL_PATH:-/opt/models/failure-detector.joblib}"
METRICS_DB="${METRICS_DB:-/var/lib/runner-metrics.db}"
ANOMALY_THRESHOLD="${ANOMALY_THRESHOLD:-0.7}"
SCORING_INTERVAL="${SCORING_INTERVAL:-10}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
LOG_FILE="${LOG_FILE:-/var/log/failure-prediction.log}"

mkdir -p "$(dirname "$MODEL_PATH")"
mkdir -p "$(dirname "$METRICS_DB")" && chmod 700 "$(dirname "$METRICS_DB")"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Feature extraction from OTEL metrics
extract_features() {
  local job_id="$1"
  
  log "📊 Extracting features for job: $job_id"
  
  # This would normally query Prometheus or the local metrics DB
  # For now, create a Python script that does this
  
  python3 << 'PYTHON_END'
import json
import sys
from datetime import datetime, timedelta

# Example feature extraction (placeholder)
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
PYTHON_END
}

# Score anomaly using pre-trained model
score_anomaly() {
  local job_id="$1"
  local features="$2"
  
  log "🔍 Scoring anomaly for job: $job_id"
  
  # Load model and score (placeholder implementation)
  python3 << 'PYTHON_END'
import json
import sys
import joblib
from pathlib import Path

MODEL_PATH = "/opt/models/failure-detector.joblib"
THRESHOLD = 0.7

# In production, would load actual trained model
# model = joblib.load(MODEL_PATH)

# Example score (normally from model.decision_function())
anomaly_score = 0.45  # Normal job

features = json.loads(sys.stdin.read())

# This would be: anomaly_score = model.decision_function([list(features.values())])

result = {
  "job_id": "job-123",
  "anomaly_score": anomaly_score,
  "is_anomalous": anomaly_score > THRESHOLD,
  "risk_level": "low" if anomaly_score < 0.5 else "medium" if anomaly_score < 0.8 else "high",
  "confidence": min(abs(anomaly_score - THRESHOLD) / 0.3, 1.0),
  "top_features": [
      {"name": "duration_variance", "importance": 0.35},
      {"name": "error_rate", "importance": 0.25},
      {"name": "cpu_usage_spike", "importance": 0.20},
  ]
}

print(json.dumps(result, indent=2))
PYTHON_END
}

# Generate alert for anomalous job
send_alert() {
  local job_id="$1"
  local anomaly_score="$2"
  local risk_level="$3"
  
  log "⚠️  Job anomaly detected: $job_id (score: $anomaly_score, risk: $risk_level)"
  
  # Send to webhook if configured (with retries)
  if [ -n "$ALERT_WEBHOOK" ]; then
    local payload=$(cat <<EOF
{
  "job_id": "$job_id",
  "anomaly_score": $anomaly_score,
  "risk_level": "$risk_level",
  "timestamp": "$(date -Iseconds)",
  "message": "Job $job_id shows anomalous behavior (risk: $risk_level)",
  "recommendation": "Monitor job closely or consider preemption if risk is high"
}
EOF
)

    local attempt=0
    local max_attempts=3
    local backoff=2
    while [ $attempt -lt $max_attempts ]; do
      if curl -s -S -X POST "$ALERT_WEBHOOK" -H "Content-Type: application/json" -d "$payload" --connect-timeout 5 --max-time 10 > /dev/null 2>&1; then
        break
      fi
      attempt=$((attempt+1))
      sleep $((backoff * attempt))
    done
  fi
  
  # Log to local database
  # Write prediction with a simple retry in case of transient DB lock
  local db_attempt=0
  while [ $db_attempt -lt 3 ]; do
    if sqlite3 "$METRICS_DB" "INSERT INTO predictions (job_id, anomaly_score, risk_level, timestamp) VALUES ('$job_id', $anomaly_score, '$risk_level', datetime('now'));"; then
      break
    fi
    db_attempt=$((db_attempt+1))
    sleep 1
  done
}

# Monitor running jobs and detect anomalies
monitor_jobs() {
  log "👁️  Starting job monitoring service (interval: ${SCORING_INTERVAL}s)"
  
  while true; do
    # Get all running jobs from health monitor
    local running_jobs
    running_jobs=$(pgrep -f "github-runner" 2>/dev/null || true)
    if [ -z "$running_jobs" ]; then
      sleep "$SCORING_INTERVAL"
      continue
    fi

    running_jobs=$(echo "$running_jobs" | awk '{print "job-"$1}')
    
    for job_id in $running_jobs; do
      # Extract features
      local features=$(extract_features "$job_id")
      
      if [ -z "$features" ]; then
        continue
      fi
      
      # Score anomaly
      local score_result=$(echo "$features" | score_anomaly "$job_id" "$features")
      
      # Parse result
      local anomaly_score=$(echo "$score_result" | jq -r '.anomaly_score')
      local is_anomalous=$(echo "$score_result" | jq -r '.is_anomalous')
      local risk_level=$(echo "$score_result" | jq -r '.risk_level')
      
      # Alert if anomalous
      if [ "$is_anomalous" = "true" ]; then
        send_alert "$job_id" "$anomaly_score" "$risk_level"
      fi
    done
    
    sleep "$SCORING_INTERVAL"
  done
}

# Train model from historical data
train_model() {
  local data_file="$1"
  
  log "🤖 Training failure detection model from: $data_file"
  
  python3 << 'PYTHON_END'
import sys
import pandas as pd
import joblib
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler

# Load historical data (OTEL traces converted to features)
data_file = sys.argv[1] if len(sys.argv) > 1 else "job-features.csv"

try:
  df = pd.read_csv(data_file)
  print(f"Loaded {len(df)} job records")
  
  # Feature columns (excluding target)
  feature_cols = [
      'cpu_usage_spike', 'memory_usage_spike', 'disk_write_rate',
      'network_connections', 'process_count', 'error_rate',
      'duration_variance', 'exit_code_history'
  ]
  
  X = df[feature_cols]
  
  # Normalize features
  scaler = StandardScaler()
  X_scaled = scaler.fit_transform(X)
  
  # Train Isolation Forest
  model = IsolationForest(
    contamination=0.1,  # Expect ~10% anomalies
    random_state=42,
    n_estimators=100
  )
  model.fit(X_scaled)
  
  # Save model
  joblib.dump(model, '/opt/models/failure-detector.joblib')
  joblib.dump(scaler, '/opt/models/feature-scaler.joblib')
  
  print("✓ Model trained and saved")
  
except Exception as e:
  print(f"ERROR: Training failed: {e}")
  sys.exit(1)
PYTHON_END
}

# Evaluate model performance
evaluate_model() {
  local test_file="$1"
  
  log "📈 Evaluating model: $test_file"
  
  python3 << 'PYTHON_END'
import sys
import pandas as pd
import joblib
from sklearn.metrics import confusion_matrix, roc_auc_score

model_path = "/opt/models/failure-detector.joblib"
scaler_path = "/opt/models/feature-scaler.joblib"

# Load model and scaler
model = joblib.load(model_path)
scaler = joblib.load(scaler_path)

# Load test data
test_file = sys.argv[1] if len(sys.argv) > 1 else "test-features.csv"
df = pd.read_csv(test_file)

feature_cols = [
    'cpu_usage_spike', 'memory_usage_spike', 'disk_write_rate',
    'network_connections', 'process_count', 'error_rate',
    'duration_variance', 'exit_code_history'
]

X = df[feature_cols]
y = df.get('is_failure', [0] * len(df))  # True labels if available

X_scaled = scaler.transform(X)
predictions = model.predict(X_scaled)

# Confusion matrix
cm = confusion_matrix(y, predictions)
print(f"Confusion Matrix:\n{cm}")

# Calculate metrics
accuracy = (cm[0,0] + cm[1,1]) / cm.sum()
precision = cm[1,1] / (cm[1,1] + cm[0,1]) if (cm[1,1] + cm[0,1]) > 0 else 0
recall = cm[1,1] / (cm[1,1] + cm[1,0]) if (cm[1,1] + cm[1,0]) > 0 else 0

print(f"\nMetrics:")
print(f"  Accuracy: {accuracy:.2%}")
print(f"  Precision: {precision:.2%}")
print(f"  Recall: {recall:.2%}")
PYTHON_END
}

# CLI
main() {
  case "${1:-help}" in
    monitor)
      monitor_jobs
      ;;
    train)
      train_model "${2:-.}"
      ;;
    evaluate)
      evaluate_model "${2:-.}"
      ;;
    *)
      cat <<'HELP'
Failure Prediction Service - Phase P1

Usage:
  failure-predictor monitor                          Start monitoring service
  failure-predictor train <data-file>               Train model from historical data
  failure-predictor evaluate <test-file>            Evaluate model performance

Environment Variables:
  MODEL_PATH              Path to trained model (default: /opt/models/failure-detector.joblib)
  ANOMALY_THRESHOLD       Anomaly score threshold (default: 0.7)
  SCORING_INTERVAL        Check interval seconds (default: 10)
  ALERT_WEBHOOK          Webhook URL for alerts

Features Analyzed:
  - CPU usage spikes
  - Memory pressure
  - Disk I/O rate
  - Network connections
  - Process count
  - Error rate
  - Duration variance
  - Historical success rate

Risk Levels:
  low      (score <0.5)   - Normal behavior
  medium   (score 0.5-0.8) - Worth monitoring
  high     (score >0.8)   - Likely to fail soon

Training Data Format (CSV):
  cpu_usage_spike,memory_usage_spike,disk_write_rate,...,is_failure
  2.5,1.8,450,42,18,0.05,1.2,0.95,0

Examples:
  failure-predictor monitor &
  failure-predictor train ./historical-jobs.csv
  failure-predictor evaluate ./test-jobs.csv

HELP
      exit 1
      ;;
  esac
}

main "$@"
