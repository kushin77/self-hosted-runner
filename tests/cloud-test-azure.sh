#!/usr/bin/env bash
# Azure Deployment Verification Test
# Launches VMs, verifies bootstrap, validates runner registration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_LOG="${SCRIPT_DIR}/cloud-test-azure.log"

# Configuration
AZURE_SUBSCRIPTION="${AZURE_SUBSCRIPTION:-}"
RESOURCE_GROUP="${RESOURCE_GROUP:-github-runners-test-$(date +%s)}"
LOCATION="${LOCATION:-eastus}"
VM_NAME="runner-test-${RANDOM}"
IMAGE="UbuntuLTS"
VM_SIZE="Standard_B2s"

TESTS_PASSED=0
TESTS_FAILED=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${TEST_LOG}"
}

cleanup() {
  log "Cleaning up test resources..."
  
  # Delete resource group
  if [ -n "${RESOURCE_GROUP:-}" ]; then
    az group delete \
      --name="${RESOURCE_GROUP}" \
      --no-wait \
      --yes \
      || log "Failed to delete resource group"
  fi
  
  log "Cleanup initiated"
}

trap cleanup EXIT

# ============================================================================
# TEST GROUP: Pre-flight Checks
# ============================================================================

test_prerequisites() {
  log "Checking prerequisites..."
  
  # Check Azure CLI
  if ! command -v az &> /dev/null; then
    log "✗ Azure CLI not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
  fi
  
  # Check subscription
  if [ -z "${AZURE_SUBSCRIPTION}" ]; then
    log "✗ AZURE_SUBSCRIPTION not set"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
  fi
  
  # Verify authentication
  if ! az account show --subscription="${AZURE_SUBSCRIPTION}" &>/dev/null; then
    log "✗ Azure authentication failed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    exit 1
  fi
  
  log "✓ Prerequisites satisfied"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

# ============================================================================
# TEST GROUP: Resource Group
# ============================================================================

test_create_resource_group() {
  log "Creating resource group..."
  
  az group create \
    --name="${RESOURCE_GROUP}" \
    --location="${LOCATION}" \
    --subscription="${AZURE_SUBSCRIPTION}"
  
  if [ $? -ne 0 ]; then
    log "✗ Failed to create resource group"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ Resource group created: ${RESOURCE_GROUP}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

# ============================================================================
# TEST GROUP: Network Configuration
# ============================================================================

test_create_network() {
  log "Creating virtual network..."
  
  local vnet_name="runner-vnet-${RANDOM}"
  local subnet_name="runner-subnet"
  
  az network vnet create \
    --resource-group="${RESOURCE_GROUP}" \
    --name="${vnet_name}" \
    --address-prefix=10.0.0.0/16 \
    --subnet-name="${subnet_name}" \
    --subnet-prefix=10.0.0.0/24 \
    --subscription="${AZURE_SUBSCRIPTION}"
  
  if [ $? -ne 0 ]; then
    log "✗ Failed to create virtual network"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ Virtual network created"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Create NSG
  local nsg_name="runner-nsg-${RANDOM}"
  az network nsg create \
    --resource-group="${RESOURCE_GROUP}" \
    --name="${nsg_name}" \
    --subscription="${AZURE_SUBSCRIPTION}"
  
  # Allow SSH
  az network nsg rule create \
    --resource-group="${RESOURCE_GROUP}" \
    --nsg-name="${nsg_name}" \
    --name=AllowSSH \
    --priority=1000 \
    --direction=Inbound \
    --access=Allow \
    --protocol=Tcp \
    --source-address-prefixes='*' \
    --destination-port-ranges=22 \
    --subscription="${AZURE_SUBSCRIPTION}"
  
  log "✓ Network security configured"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

# ============================================================================
# TEST GROUP: VM Launch
# ============================================================================

test_launch_vm() {
  log "Launching Azure VM..."
  
  # Create SSH key
  local key_path="/tmp/runner-test-key-${RANDOM}"
  ssh-keygen -t rsa -b 4096 -f "${key_path}" -N ""
  
  # Create VM
  az vm create \
    --resource-group="${RESOURCE_GROUP}" \
    --name="${VM_NAME}" \
    --image="${IMAGE}" \
    --size="${VM_SIZE}" \
    --ssh-key-values="${key_path}.pub" \
    --public-ip-sku Standard \
    --subscription="${AZURE_SUBSCRIPTION}" \
    --query publicIpAddress \
    --output tsv > /tmp/vm_ip_${RANDOM}.txt
  
  if [ $? -ne 0 ]; then
    log "✗ Failed to launch VM"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ VM launched: ${VM_NAME}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Store key path for later use
  echo "${key_path}" > /tmp/vm_key_path.txt
}

# ============================================================================
# TEST GROUP: SSH Connectivity
# ============================================================================

test_ssh_connectivity() {
  log "Testing SSH connectivity..."
  
  # Get IP address
  local public_ip=$(az vm list-ip-addresses \
    --resource-group="${RESOURCE_GROUP}" \
    --name="${VM_NAME}" \
    --subscription="${AZURE_SUBSCRIPTION}" \
    --query [0].virtualMachines[0].ipAddresses[0].publicIpAddress \
    --output tsv)
  
  if [ -z "${public_ip}" ] || [ "${public_ip}" == "None" ] || [ "${public_ip}" == "null" ]; then
    log "✗ No public IP assigned"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  log "✓ Public IP: ${public_ip}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  
  # Get key path
  local key_path=$(cat /tmp/vm_key_path.txt 2>/dev/null || echo "")
  
  if [ -z "${key_path}" ]; then
    log "✗ SSH key not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  
  # Wait for SSH
  local max_attempts=30
  local attempt=0
  
  while [ ${attempt} -lt ${max_attempts} ]; do
    if ssh -i "${key_path}" \
           -o StrictHostKeyChecking=no \
           -o ConnectTimeout=5 \
           azureuser@"${public_ip}" \
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
  
  local key_path=$(cat /tmp/vm_key_path.txt 2>/dev/null || echo "")
  local public_ip=$(az vm list-ip-addresses \
    --resource-group="${RESOURCE_GROUP}" \
    --name="${VM_NAME}" \
    --subscription="${AZURE_SUBSCRIPTION}" \
    --query [0].virtualMachines[0].ipAddresses[0].publicIpAddress \
    --output tsv)
  
  # Check runner installation
  if ssh -i "${key_path}" \
         -o StrictHostKeyChecking=no \
         azureuser@"${public_ip}" \
         "[ -d /opt/actions-runner ]" 2>/dev/null; then
    log "✓ Runner directory exists"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    log "✗ Runner directory not found"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  
  # Check systemd service
  if ssh -i "${key_path}" \
         -o StrictHostKeyChecking=no \
         azureuser@"${public_ip}" \
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
  
  local key_path=$(cat /tmp/vm_key_path.txt 2>/dev/null || echo "")
  local public_ip=$(az vm list-ip-addresses \
    --resource-group="${RESOURCE_GROUP}" \
    --name="${VM_NAME}" \
    --subscription="${AZURE_SUBSCRIPTION}" \
    --query [0].virtualMachines[0].ipAddresses[0].publicIpAddress \
    --output tsv)
  
  # Check Docker
  if ssh -i "${key_path}" \
         -o StrictHostKeyChecking=no \
         azureuser@"${public_ip}" \
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
    if ssh -i "${key_path}" \
           -o StrictHostKeyChecking=no \
           azureuser@"${public_ip}" \
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
  
  local key_path=$(cat /tmp/vm_key_path.txt 2>/dev/null || echo "")
  local public_ip=$(az vm list-ip-addresses \
    --resource-group="${RESOURCE_GROUP}" \
    --name="${VM_NAME}" \
    --subscription="${AZURE_SUBSCRIPTION}" \
    --query [0].virtualMachines[0].ipAddresses[0].publicIpAddress \
    --output tsv)
  
  # Check runner-env.yaml
  if ssh -i "${key_path}" \
         -o StrictHostKeyChecking=no \
         azureuser@"${public_ip}" \
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
  
  local key_path=$(cat /tmp/vm_key_path.txt 2>/dev/null || echo "")
  local public_ip=$(az vm list-ip-addresses \
    --resource-group="${RESOURCE_GROUP}" \
    --name="${VM_NAME}" \
    --subscription="${AZURE_SUBSCRIPTION}" \
    --query [0].virtualMachines[0].ipAddresses[0].publicIpAddress \
    --output tsv)
  
  if ssh -i "${key_path}" \
         -o StrictHostKeyChecking=no \
         azureuser@"${public_ip}" \
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
  log "Azure Deployment Test"
  log "========================================="
  log ""
  
  test_prerequisites
  test_create_resource_group
  test_create_network
  test_launch_vm
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
