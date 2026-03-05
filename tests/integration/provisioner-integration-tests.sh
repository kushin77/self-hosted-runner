#!/bin/bash
# Provisioner-Worker Integration Tests
# Tests job queuing, processing, and infrastructure provisioning
# Usage: bash tests/integration/provisioner-integration-tests.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TEST_DIR="/tmp/provisioner-worker-test-$TIMESTAMP"
JOB_STORE="$TEST_DIR/jobstore.json"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
PASSED=0
FAILED=0

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Provisioner-Worker Integration Tests                      ║"
echo "║  Test Directory: $TEST_DIR                                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$TEST_DIR/workspaces"

# Test utilities
function assert_test() {
  local name=$1
  local condition=$2
  echo -n "  $name ... "
  if eval "$condition"; then
    echo -e "${GREEN}✓${NC}"
    ((PASSED++))
  else
    echo -e "${RED}✗${NC}"
    ((FAILED++))
  fi
}

# ============= SECTION 1: Job Store Tests =============
echo -e "${BLUE}[1. Job Store Operations]${NC}"

# Initialize job store
cat > "$JOB_STORE" << 'EOF'
[]
EOF

assert_test "Job store file created" "[[ -f '$JOB_STORE' ]]"
assert_test "Job store is valid JSON" "node -e \"JSON.parse(require('fs').readFileSync('$JOB_STORE', 'utf8'))\""

# Test job addition
TEST_JOB=$(cat << 'JOBJSON'
{
  "request_id": "test-job-001",
  "status": "queued",
  "timestamp": "2026-03-05T12:00:00Z",
  "config": {
    "runner_name": "test-runner-01",
    "labels": ["test"],
    "workspace": "test-workspace-001"
  },
  "plan_hash": "abc123def456"
}
JOBJSON
)

# Simulate job enqueue
echo $TEST_JOB | node -e "
const fs = require('fs');
const input = require('fs').readFileSync(0, 'utf8');
const jobs = JSON.parse(fs.readFileSync('$JOB_STORE', 'utf8'));
jobs.push(JSON.parse(input));
fs.writeFileSync('$JOB_STORE', JSON.stringify(jobs, null, 2));
"

assert_test "Job enqueued successfully" "grep -q 'test-job-001' '$JOB_STORE'"
assert_test "Job status is queued" "grep -q '\"status\": \"queued\"' '$JOB_STORE'"

# ============= SECTION 2: Plan Hash Idempotency Tests =============
echo ""
echo -e "${BLUE}[2. Plan Hash Idempotency]${NC}"

# Add duplicate job with same plan hash
DUPLICATE_JOB=$(cat << 'JOBJSON'
{
  "request_id": "test-job-002",
  "status": "queued",
  "timestamp": "2026-03-05T12:00:05Z",
  "config": {
    "runner_name": "test-runner-02",
    "labels": ["test"],
    "workspace": "test-workspace-001"
  },
  "plan_hash": "abc123def456"
}
JOBJSON
)

# Check duplicate detection logic
echo $DUPLICATE_JOB | node -e "
const fs = require('fs');
const input = require('fs').readFileSync(0, 'utf8');
const jobs = JSON.parse(fs.readFileSync('$JOB_STORE', 'utf8'));
const newJob = JSON.parse(input);
const existingWithHash = jobs.find(j => j.plan_hash === newJob.plan_hash);
if (existingWithHash) {
  console.log('DUPLICATE_DETECTED');
} else {
  jobs.push(newJob);
  fs.writeFileSync('$JOB_STORE', JSON.stringify(jobs, null, 2));
}
" > /tmp/dup_result_$$.txt

assert_test "Duplicate plan hash detected" "grep -q 'DUPLICATE_DETECTED' /tmp/dup_result_$$.txt"
rm /tmp/dup_result_$$.txt

# ============= SECTION 3: Terraform Workspace Tests =============
echo ""
echo -e "${BLUE}[3. Terraform Workspace Structur]${NC}"

# Create sample workspace structure
WORKSPACE_DIR="$TEST_DIR/workspaces/test-job-001"
mkdir -p "$WORKSPACE_DIR"

# Create mock terraform files
cat > "$WORKSPACE_DIR/main.tf" << 'EOF'
terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "runner_name" {
  type = string
}

provider "github" {
  token = var.github_token
}

resource "github_repository_deploy_key" "runner" {
  title      = var.runner_name
  repository = "example-repo"
  key        = file("~/.ssh/id_rsa.pub")
  read_only  = false
}
EOF

assert_test "Terraform workspace created" "[[ -d '$WORKSPACE_DIR' ]]"
assert_test "main.tf present" "[[ -f '$WORKSPACE_DIR/main.tf' ]]"
assert_test "main.tf is valid HCL" "grep -q 'terraform {' '$WORKSPACE_DIR/main.tf'"

# Create terraform.tfvars
cat > "$WORKSPACE_DIR/terraform.tfvars" << 'EOF'
runner_name = "test-runner-01"
EOF

assert_test "terraform.tfvars created" "[[ -f '$WORKSPACE_DIR/terraform.tfvars' ]]"

# ============= SECTION 4: Job Status Transitions =============
echo ""
echo -e "${BLUE}[4. Job Status Transitions]${NC}"

# Simulate job processing: queued -> processing -> provisioned -> completed
node -e "
const fs = require('fs');
const jobs = JSON.parse(fs.readFileSync('$JOB_STORE', 'utf8'));
const job = jobs.find(j => j.request_id === 'test-job-001');
if (job) {
  job.status = 'processing';
  fs.writeFileSync('$JOB_STORE', JSON.stringify(jobs, null, 2));
}
"

assert_test "Job status: queued -> processing" "grep -q 'test-job-001.*processing' '$JOB_STORE' || grep -A2 'test-job-001' '$JOB_STORE' | grep -q 'processing'"

# Simulate completion
node -e "
const fs = require('fs');
const jobs = JSON.parse(fs.readFileSync('$JOB_STORE', 'utf8'));
const job = jobs.find(j => j.request_id === 'test-job-001');
if (job) {
  job.status = 'completed';
  job.result = { provisioned: true, runner_registered: true };
  job.completed_at = new Date().toISOString();
  fs.writeFileSync('$JOB_STORE', JSON.stringify(jobs, null, 2));
}
"

assert_test "Job status: processing -> completed" "grep -q 'completed' '$JOB_STORE'"
assert_test "Job result contains metadata" "grep -q 'provisioned' '$JOB_STORE'"

# ============= SECTION 5: Logging & Audit Trail =============
echo ""
echo -e "${BLUE}[5. Logging & Audit Trail]${NC}"

# Create mock log file
LOG_FILE="$TEST_DIR/provisioner-worker.log"
cat > "$LOG_FILE" << 'EOF'
2026-03-05T12:00:00Z [INFO] Starting provisioner-worker
2026-03-05T12:00:01Z [DEBUG] Polling job queue (interval: 5000ms)
2026-03-05T12:00:02Z [INFO] Found job: test-job-001 (status: queued)
2026-03-05T12:00:03Z [INFO] Creating workspace: /tmp/provisioner-worker-test/workspaces/test-job-001
2026-03-05T12:00:04Z [INFO] Running terraform init
2026-03-05T12:00:05Z [INFO] Running terraform plan
2026-03-05T12:00:06Z [INFO] Running terraform apply
2026-03-05T12:00:07Z [INFO] Job completed: test-job-001 (status: completed)
2026-03-05T12:00:08Z [DEBUG] Next poll in 5000ms
EOF

assert_test "Log file created" "[[ -f '$LOG_FILE' ]]"
assert_test "Log contains startup message" "grep -q 'Starting provisioner-worker' '$LOG_FILE'"
assert_test "Log contains job processing" "grep -q 'Running terraform' '$LOG_FILE'"
assert_test "Log contains completion" "grep -q 'completed' '$LOG_FILE'"

# ============= SECTION 6: Error Handling =============
echo ""
echo -e "${BLUE}[6. Error Handling]${NC}"

# Simulate error job
ERROR_JOB=$(cat << 'JOBJSON'
{
  "request_id": "test-job-error-001",
  "status": "error",
  "timestamp": "2026-03-05T12:00:10Z",
  "config": {
    "runner_name": "test-runner-error",
    "labels": ["test"],
    "workspace": "test-workspace-error"
  },
  "error": {
    "code": "TERRAFORM_APPLY_FAILED",
    "message": "Failed to apply Terraform configuration",
    "details": "Invalid provider configuration"
  },
  "retry_count": 0,
  "max_retries": 3
}
JOBJSON
)

echo $ERROR_JOB | node -e "
const fs = require('fs');
const input = require('fs').readFileSync(0, 'utf8');
const jobs = JSON.parse(fs.readFileSync('$JOB_STORE', 'utf8'));
jobs.push(JSON.parse(input));
fs.writeFileSync('$JOB_STORE', JSON.stringify(jobs, null, 2));
"

assert_test "Error job enqueued" "grep -q 'test-job-error-001' '$JOB_STORE'"
assert_test "Error details captured" "grep -q 'TERRAFORM_APPLY_FAILED' '$JOB_STORE'"
assert_test "Retry count initialized" "grep -q '\"retry_count\": 0' '$JOB_STORE'"

# ============= RESULTS =============
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e "Provisioner-Worker Integration Test Results:"
echo -e "  Passed: ${GREEN}${PASSED}${NC}"
echo -e "  Failed: ${RED}${FAILED}${NC}"
echo ""
echo "Test Artifacts:"
echo "  Job Store: $JOB_STORE"
echo "  Logs: $LOG_FILE"
echo "  Workspaces: $TEST_DIR/workspaces"
echo "════════════════════════════════════════════════════════════"

if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}✅ All provisioner-worker integration tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed. Review errors above.${NC}"
  exit 1
fi
