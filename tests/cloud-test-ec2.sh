#!/usr/bin/env bash
# AWS EC2 Deployment Verification Test
# Launches instances, verifies bootstrap, validates runner registration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_LOG="${SCRIPT_DIR}/cloud-test-ec2.log"

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
IMAGE_ID="${IMAGE_ID:-ami-0885b1f6bd170450c}"  # Ubuntu 20.04 LTS
TEST_TAG="github-runner-test-$(date +%s)"
RUNNER_TOKEN="${GITHUB_TOKEN:-}"

TESTS_PASSED=0
TESTS_FAILED=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${TEST_LOG}"
}

cleanup() {
  log "Cleaning up test resources..."
  
  # Terminate instances
  if [ -n "${INSTANCE_ID:-}" ]; then
    aws ec2 terminate-instances \
      --instance-ids "${INSTANCE_ID}" \
      --region="${AWS_REGION}" \
      || log "Failed to terminate instance"
  fi
  
  # Wait for termination
  if [ -n "${INSTANCE_ID:-}" ]; then
    aws ec2 wait instance-terminated \
      --instance-ids "${INSTANCE_ID}" \
      --region="${AWS_REGION}" \
      || log "Timeout waiting for termination"
  fi
  
  log "Cleanup complete"
}

trap cleanup EXIT

# ============================================================================
# TEST GROUP: Pre-flight Checks
# ============================================================================

test_prerequisites() {
  log "Checking prerequisites..."
  
  # Check AWS CLI
  if ! command -v aws &> /dev/null; then
    log "✗ AWS CLI not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
  fi
  
  # Check authentication
  if ! aws sts get-caller-identity --region="${AWS_REGION}" &> /dev/null; then
    log "✗ AWS authentication failed"
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
  log "Launching EC2 instance..."
  
  # Create security group
  local sg_name="runner-test-sg-${RANDOM}"
  local sg_id=$(aws ec2 create-security-group \
    --group-name="${sg_name}" \
    --description="Test security group" \
    --region="${AWS_REGION}" \
    --query 'GroupId' \
    --output text)
  
  if [ -z "${sg_id}" ]; then
    log "✗ Failed to create security group"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ Security group created: ${sg_id}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Allow SSH
  aws ec2 authorize-security-group-ingress \
    --group-id="${sg_id}" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region="${AWS_REGION}" || true
  
  # Create key pair
  local key_name="runner-test-key-${RANDOM}"
  aws ec2 create-key-pair \
    --key-name="${key_name}" \
    --region="${AWS_REGION}" \
    --query 'KeyMaterial' \
    --output text > /tmp/"${key_name}".pem
  
  chmod 600 /tmp/"${key_name}".pem
  
  log "✓ Key pair created: ${key_name}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Launch instance
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id="${IMAGE_ID}" \
    --instance-type="${INSTANCE_TYPE}" \
    --key-name="${key_name}" \
    --security-group-ids="${sg_id}" \
    --tag-specifications="ResourceType=instance,Tags=[{Key=Name,Value=${TEST_TAG}},{Key=test,Value=true}]" \
    --region="${AWS_REGION}" \
    --query 'Instances[0].InstanceId' \
    --output text)
  
  if [ -z "${INSTANCE_ID}" ]; then
    log "✗ Failed to launch instance"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ Instance launched: ${INSTANCE_ID}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Store for cleanup
  trap "cleanup" EXIT
  
  # Wait for running state
  log "Waiting for instance to be running..."
  aws ec2 wait instance-running \
    --instance-ids="${INSTANCE_ID}" \
    --region="${AWS_REGION}"
  
  log "✓ Instance is running"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

# ============================================================================
# TEST GROUP: SSH Connectivity
# ============================================================================

test_ssh_connectivity() {
  log "Testing SSH connectivity..."
  
  # Get public IP
  local public_ip=$(aws ec2 describe-instances \
    --instance-ids="${INSTANCE_ID}" \
    --region="${AWS_REGION}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
  
  if [ -z "${public_ip}" ] || [ "${public_ip}" == "None" ]; then
    log "✗ No public IP assigned"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ Public IP: ${public_ip}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Wait for SSH
  local max_attempts=30
  local attempt=0
  
  while [ ${attempt} -lt ${max_attempts} ]; do
    if ssh -i /tmp/"${key_name}".pem \
           -o StrictHostKeyChecking=no \
           -o ConnectTimeout=5 \
           ubuntu@"${public_ip}" \
           "echo 'SSH connected'" &> /dev/null; then
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
  if ssh -i /tmp/"${key_name}".pem \
         -o StrictHostKeyChecking=no \
         ubuntu@"${public_ip}" \
         "[ -d /opt/actions-runner ]" 2>/dev/null; then
    log "✓ Runner directory exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "✗ Runner directory not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  
  # Check systemd service
  if ssh -i /tmp/"${key_name}".pem \
         -o StrictHostKeyChecking=no \
         ubuntu@"${public_ip}" \
         "systemctl is-enabled actions-runner" 2>/dev/null; then
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
  if ssh -i /tmp/"${key_name}".pem \
         -o StrictHostKeyChecking=no \
         ubuntu@"${public_ip}" \
         "docker ps" &>/dev/null; then
    log "✓ Docker is running"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "✗ Docker is not running"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  
  # Check dependencies
  local deps=(docker git curl cosign syft conftest)
  for dep in "${deps[@]}"; do
    if ssh -i /tmp/"${key_name}".pem \
           -o StrictHostKeyChecking=no \
           ubuntu@"${public_ip}" \
           "which ${dep}" &>/dev/null; then
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
  if ssh -i /tmp/"${key_name}".pem \
         -o StrictHostKeyChecking=no \
         ubuntu@"${public_ip}" \
         "[ -f /opt/runner-config/runner-env.yaml ]" 2>/dev/null; then
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
  
  if ssh -i /tmp/"${key_name}".pem \
         -o StrictHostKeyChecking=no \
         ubuntu@"${public_ip}" \
         "[ -f /var/log/runner-bootstrap.log ]" 2>/dev/null; then
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
  log "AWS EC2 Deployment Test"
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
