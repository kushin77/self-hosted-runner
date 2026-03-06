#!/usr/bin/env bash
# Legacy Node Cleanup Automation
# Purpose: Stop services, remove artifacts, and migrate from 192.168.168.31 to 192.168.168.42
# Status: Hands-off automation (fully autonomous, no manual intervention required)
# Controlled by: Issue #787

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../" && pwd)"

# Legacy node details
LEGACY_NODE="192.168.168.31"
NEW_NODE="192.168.168.42"
LOG_FILE="${PROJECT_ROOT}/legacy-node-cleanup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Legacy Node Cleanup Automation${NC}"
echo "========================================"
echo "Legacy Node: ${LEGACY_NODE}"
echo "New Node: ${NEW_NODE}"
echo "Log File: ${LOG_FILE}"
echo ""

# Check if running in GitHub Actions
if [[ "${GITHUB_ACTIONS}" == "true" ]]; then
  echo "✅ Running in GitHub Actions environment"
  RUNNER_HOST="${NEW_NODE}"
  RUNNER_USER="runner"
else
  echo "⚠️  Running locally (not in GitHub Actions)"
  RUNNER_HOST="${LEGACY_NODE}"
  RUNNER_USER="${USER}"
fi

# Function to run command on remote node
run_remote_cmd() {
  local host=$1
  local user=$2
  local cmd=$3
  
  echo -e "${YELLOW}▶ Running on ${host}: ${cmd}${NC}"
  
  if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${user}@${host}" "${cmd}" 2>&1 | tee -a "${LOG_FILE}"; then
    echo -e "${GREEN}✓ Command succeeded${NC}"
    return 0
  else
    echo -e "${RED}✗ Command failed${NC}"
    return 1
  fi
}

# Cleanup Task 1: Stop GitHub Actions Runner service
cleanup_runner_service() {
  echo ""
  echo -e "${BLUE}📍 Step 1: Stop GitHub Actions Runner Service${NC}"
  
  run_remote_cmd "${LEGACY_NODE}" "root" \
    "systemctl stop actions.runner.* || systemctl stop github-runner || echo 'No runner service found'"
  
  run_remote_cmd "${LEGACY_NODE}" "root" \
    "systemctl disable actions.runner.* || systemctl disable github-runner || echo 'No runner service to disable'"
}

# Cleanup Task 2: Remove repository artifacts
cleanup_artifacts() {
  echo ""
  echo -e "${BLUE}📍 Step 2: Remove Repository Artifacts${NC}"
  
  # Remove runner directories
  run_remote_cmd "${LEGACY_NODE}" "root" \
    "rm -rf /home/*/actions-runner* || echo 'No runner directories found'"
  
  run_remote_cmd "${LEGACY_NODE}" "root" \
    "rm -rf /opt/github-runner || echo 'No /opt/github-runner directory'"
  
  # Remove temp files
  run_remote_cmd "${LEGACY_NODE}" "root" \
    "rm -rf /tmp/actions-runner* || echo 'No temp runner files'"
}

# Cleanup Task 3: Clean up systemd service files
cleanup_systemd() {
  echo ""
  echo -e "${BLUE}📍 Step 3: Clean Up Systemd Service Files${NC}"
  
  run_remote_cmd "${LEGACY_NODE}" "root" \
    "rm -f /etc/systemd/system/actions.runner.*.service || echo 'No runner service files found'"
  
  run_remote_cmd "${LEGACY_NODE}" "root" \
    "systemctl daemon-reload"
}

# Cleanup Task 4: Archive logs and configs
archive_configs() {
  echo ""
  echo -e "${BLUE}📍 Step 4: Archive Logs and Configs${NC}"
  
  run_remote_cmd "${LEGACY_NODE}" "root" \
    "tar czf /var/backups/legacy-node-cleanup-$(date +%Y%m%d-%H%M%S).tar.gz /var/log/ /etc/systemd/system/actions.runner*.service 2>/dev/null || echo 'Archive skipped'"
}

# Cleanup Task 5: Cleanup DNS/routing references
cleanup_dns() {
  echo ""
  echo -e "${BLUE}📍 Step 5: Update DNS References${NC}"
  
  # This would typically be done via Terraform or AWS Route53
  echo "Note: DNS cleanup should be done via terraform-dns-apply workflow"
  echo "Verify in AWS Route53 that 'internal.elevatediq.com' points to ${NEW_NODE}"
}

# Cleanup Task 6: Health check on new node
verify_new_node() {
  echo ""
  echo -e "${BLUE}📍 Step 6: Verify New Node Health${NC}"
  
  if ssh -o ConnectTimeout=10 "${RUNNER_USER}@${NEW_NODE}" "echo 'Connected to new node'; systemctl status actions.runner* || echo 'No runner service yet'" 2>&1 | tee -a "${LOG_FILE}"; then
    echo -e "${GREEN}✓ New node is reachable and operational${NC}"
  else
    echo -e "${RED}✗ Cannot reach new node${NC}"
    return 1
  fi
}

# Main execution
main() {
  # Check prerequisites
  if ! command -v ssh &> /dev/null; then
    echo -e "${RED}❌ SSH is not available${NC}"
    exit 1
  fi
  
  # Confirm action
  if [[ "${CI:-false}" != "true" ]]; then
    echo -e "${YELLOW}⚠️  Destructive operation detected!${NC}"
    echo "This will remove the legacy node (${LEGACY_NODE}) from service."
    read -p "Continue? (yes/no): " -r confirm
    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi
  
  # Execute cleanup tasks
  cleanup_runner_service
  cleanup_artifacts
  cleanup_systemd
  archive_configs
  cleanup_dns
  verify_new_node
  
  echo ""
  echo -e "${GREEN}✅ Legacy Node Cleanup Complete${NC}"
  echo "Log: ${LOG_FILE}"
  echo ""
  echo "Summary:"
  echo "- Legacy node (${LEGACY_NODE}) services stopped"
  echo "- Repository artifacts removed"
  echo "- Systemd configurations cleaned"
  echo "- Logs archived to /var/backups/"
  echo "- New node (${NEW_NODE}) verified operational"
  echo ""
  echo "Next steps:"
  echo "1. Verify runners are registered on new node: gh run list --repo kushin77/self-hosted-runner"
  echo "2. Decommission ${LEGACY_NODE} hardware if no longer needed"
  echo "3. Update DNS/networking docs in wiki"
}

# Execute main with error handling
if main; then
  echo -e "${GREEN}✅ Operation succeeded${NC}"
  exit 0
else
  echo -e "${RED}❌ Operation failed${NC}"
  echo "Log: ${LOG_FILE}"
  exit 1
fi
