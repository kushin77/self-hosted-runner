#!/usr/bin/env bash
# GCP Deployment Verification Test
# Launches instances, verifies bootstrap, validates runner registration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_LOG="${SCRIPT_DIR}/cloud-test-gcp.log"

# Configuration
GCP_PROJECT="${GCP_PROJECT:-}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
GCP_REGION="${GCP_REGION:-us-central1}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-medium}"
IMAGE_FAMILY="ubuntu-2004-lts"
IMAGE_PROJECT="ubuntu-os-cloud"
TEST_TAG="github-runner-test-$(date +%s)"
INSTANCE_NAME="runner-test-${RANDOM}"

TESTS_PASSED=0
TESTS_FAILED=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${TEST_LOG}"
}

cleanup() {
  log "Cleaning up test resources..."
  
  # Delete instance
  if [ -n "${INSTANCE_NAME:-}" ]; then
    gcloud compute instances delete \
      "${INSTANCE_NAME}" \
      --project="${GCP_PROJECT}" \
      --zone="${GCP_ZONE}" \
      --quiet \
      || log "Failed to delete instance"
  fi
  
  log "Cleanup complete"
}

trap cleanup EXIT

# ============================================================================
# TEST GROUP: Pre-flight Checks
# ============================================================================

test_prerequisites() {
  log "Checking prerequisites..."
  
  # Check gcloud CLI
  if ! command -v gcloud &> /dev/null; then
    log "✗ gcloud CLI not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
  fi
  
  # Check project
  if [ -z "${GCP_PROJECT}" ]; then
    log "✗ GCP_PROJECT not set"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
  fi
  
  # Verify authentication
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
    log "✗ GCP authentication failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
  fi
  
  log "✓ Prerequisites satisfied"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

# ============================================================================
# TEST GROUP: Instance Launch
# ============================================================================

test_launch_instance() {
  log "Launching GCP instance..."
  
  # Create firewall rule
  local fw_rule_name="allow-ssh-${RANDOM}"
  gcloud compute firewall-rules create "${fw_rule_name}" \
    --project="${GCP_PROJECT}" \
    --allow=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --priority=1000 \
    --quiet || true
  
  log "✓ Firewall rule created: ${fw_rule_name}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Get latest image
  local image=$(gcloud compute images list \
    --project="${IMAGE_PROJECT}" \
    --filter="family:${IMAGE_FAMILY}" \
    --format="value(name)" \
    --limit=1)
  
  if [ -z "${image}" ]; then
    log "✗ Failed to find image"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ Image found: ${image}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Launch instance
  gcloud compute instances create "${INSTANCE_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GCP_ZONE}" \
    --machine-type="${MACHINE_TYPE}" \
    --image="${image}" \
    --image-project="${IMAGE_PROJECT}" \
    --metadata-from-file=startup-script=bootstrap-script.sh \
    --tags=runner,test \
    --quiet
  
  if [ $? -ne 0 ]; then
    log "✗ Failed to launch instance"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ Instance launched: ${INSTANCE_NAME}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Wait for startup script
  log "Waiting for instance initialization..."
  sleep 30
}

# ============================================================================
# TEST GROUP: SSH Connectivity
# ============================================================================

test_ssh_connectivity() {
  log "Testing SSH connectivity..."
  
  # Get external IP
  local external_ip=$(gcloud compute instances describe "${INSTANCE_NAME}" \
    --project="${GCP_PROJECT}" \
    --zone="${GCP_ZONE}" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
  
  if [ -z "${external_ip}" ] || [ "${external_ip}" == "None" ]; then
    log "✗ No external IP assigned"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ External IP: ${external_ip}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Wait for SSH
  local max_attempts=30
  local attempt=0
  
  while [ ${attempt} -lt ${max_attempts} ]; do
    if gcloud compute ssh "${INSTANCE_NAME}" \
           --project="${GCP_PROJECT}" \
           --zone="${GCP_ZONE}" \
           --command="echo 'SSH connected'" 2>&1 | grep -q "SSH connected"; then
      log "✓ SSH connection successful"
      TESTS_PASSED=$((TESTS_PASSED + 1))
      return 0
    fi
    
    attempt=$((attempt + 1))
    log "SSH attempt ${attempt}/${max_attempts}..."
    sleep 2
  done
  
  log "✗ SSH connection failed after ${max_attempts} attempts"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  return 1
}

# ============================================================================
# TEST GROUP: Bootstrap Verification
# ============================================================================

test_bootstrap_execution() {
  log "Verifying bootstrap execution..."
  
  # Check runner installation
  if gcloud compute ssh "${INSTANCE_NAME}" \
         --project="${GCP_PROJECT}" \
         --zone="${GCP_ZONE}" \
         --command="[ -d /opt/actions-runner ]" 2>&1 | grep -q "True"; then
    log "✓ Runner directory exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "✗ Runner directory not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  
  # Check systemd service
  if gcloud compute ssh "${INSTANCE_NAME}" \
         --project="${GCP_PROJECT}" \
         --zone="${GCP_ZONE}" \
         --command="systemctl is-enabled actions-runner" 2>&1 | grep -q "enabled"; then
    log "✓ Runner service enabled"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "✗ Runner service not enabled"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: Health Checks
# ============================================================================

test_runner_health() {
  log "Checking runner health..."
  
  # Check Docker
  if gcloud compute ssh "${INSTANCE_NAME}" \
         --project="${GCP_PROJECT}" \
         --zone="${GCP_ZONE}" \
         --command="docker ps" 2>&1 | grep -q "CONTAINER"; then
    log "✓ Docker is running"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "✗ Docker is not running"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  
  # Check dependencies
  local deps=(docker git curl cosign syft conftest)
  for dep in "${deps[@]}"; do
    if gcloud compute ssh "${INSTANCE_NAME}" \
           --project="${GCP_PROJECT}" \
           --zone="${GCP_ZONE}" \
           --command="which ${dep}" 2>&1 | grep -q "${dep}"; then
      log "✓ ${dep} installed"
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      log "✗ ${dep} not found"
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  done
}

# ============================================================================
# TEST GROUP: Configuration
# ============================================================================

test_configuration() {
  log "Checking configuration files..."
  
  # Check runner-env.yaml
  if gcloud compute ssh "${INSTANCE_NAME}" \
         --project="${GCP_PROJECT}" \
         --zone="${GCP_ZONE}" \
         --command="[ -f /opt/runner-config/runner-env.yaml ]" 2>&1 | grep -q "True"; then
    log "✓ Configuration file exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "✗ Configuration file missing"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# TEST GROUP: Logging
# ============================================================================

test_logging() {
  log "Checking logging..."
  
  if gcloud compute ssh "${INSTANCE_NAME}" \
         --project="${GCP_PROJECT}" \
         --zone="${GCP_ZONE}" \
         --command="[ -f /var/log/runner-bootstrap.log ]" 2>&1 | grep -q "True"; then
    log "✓ Bootstrap log exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "✗ Bootstrap log not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
  log "========================================="
  log "GCP Deployment Test"
  log "========================================="
  log ""
  
  test_prerequisites
  test_launch_instance
  test_ssh_connectivity
  test_bootstrap_execution
  test_runner_health
  test_configuration
  test_logging
  
  log ""
  log "========================================="
  log "Test Results"
  log "========================================="
  log "Passed: ${TESTS_PASSED}"
  log "Failed: ${TESTS_FAILED}"
  
  if [ ${TESTS_FAILED} -gt 0 ]; then
    exit 1
  else
    exit 0
  fi
}

main "$@"
