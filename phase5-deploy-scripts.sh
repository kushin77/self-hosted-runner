#!/bin/bash
################################################################################
# PHASE 5 - AUTOMATED OPERATIONAL DEPLOYMENT
# Stage 2-3: Deploy eiq-nas integration scripts to worker/dev nodes
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKER_NODES=(192.168.168.{42..51})
readonly DEV_NODES=(192.168.168.{31..40})
readonly DEPLOY_DIR="/opt/nas"
readonly SSH_OPTS="-o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"

# Get service account SSH key from GSM
get_svc_git_key() {
  echo "[*] Retrieving svc-git SSH key from GSM..." >&2
  gcloud secrets versions access latest --secret=svc-git-ssh-key
}

# Export GSM key to temp file
export_ssh_key() {
  local tmpfile="/tmp/svc_git_key_$$"
  get_svc_git_key > "$tmpfile"
  chmod 600 "$tmpfile"
  echo "$tmpfile"
}

# Deploy script to a single node
deploy_to_node() {
  local node="$1"
  local script="$2"
  local script_name=$(basename "$script")
  local ssh_key_file="$3"
  
  echo "[*] Deploying to $node ($script_name)..."
  
  # Create deploy dir if needed
  ssh $SSH_OPTS -i "$ssh_key_file" "root@$node" "mkdir -p $DEPLOY_DIR" 2>/dev/null || true
  
  # Copy script (try scp, fall back to cat pipe ssh)
  if ! scp $SSH_OPTS -i "$ssh_key_file" "$script" "root@$node:$DEPLOY_DIR/" 2>/dev/null; then
    # Fallback: pipe script via SSH
    cat "$script" | ssh $SSH_OPTS -i "$ssh_key_file" "root@$node" "cat > $DEPLOY_DIR/$script_name"
  fi
  
  # Make executable
  ssh $SSH_OPTS -i "$ssh_key_file" "root@$node" "chmod +x $DEPLOY_DIR/$script_name"
  
  # Verify syntax
  if ssh $SSH_OPTS -i "$ssh_key_file" "root@$node" "bash -n $DEPLOY_DIR/$script_name" 2>/dev/null; then
    echo "  ✓ Deployed and verified: $script_name"
    return 0
  else
    echo "  ✗ Syntax check failed: $script_name"
    return 1
  fi
}

# Main deployment
main() {
  local ssh_key_file
  local worker_script="$SCRIPT_DIR/worker-node-nas-sync-eiqnas.sh"
  local dev_script="$SCRIPT_DIR/dev-node-nas-push-eiqnas.sh"
  local stage="$1"
  
  # Verify scripts exist
  if [[ ! -f "$worker_script" ]] || [[ ! -f "$dev_script" ]]; then
    echo "[!] ERROR: Scripts not found at $SCRIPT_DIR"
    exit 1
  fi
  
  # Get SSH key from GSM
  ssh_key_file=$(export_ssh_key)
  trap "rm -f $ssh_key_file" EXIT
  
  echo ""
  echo "================================================================================"
  echo "PHASE 5 - STAGE $stage: DEPLOYING EIQNAS SCRIPTS"
  echo "================================================================================"
  echo ""
  
  case "$stage" in
    2)
      echo "STAGE 2: Deploy to Worker Nodes (192.168.168.42-51)"
      echo ""
      local success=0
      local total=0
      for node in ${WORKER_NODES[@]}; do
        total=$((total + 1))
        if deploy_to_node "$node" "$worker_script" "$ssh_key_file"; then
          success=$((success + 1))
        fi
      done
      echo ""
      echo "Worker nodes: $success/$total successful"
      ;;
    
    3)
      echo "STAGE 3: Deploy to Dev Nodes (192.168.168.31-40)"
      echo ""
      local success=0
      local total=0
      for node in ${DEV_NODES[@]}; do
        total=$((total + 1))
        if deploy_to_node "$node" "$dev_script" "$ssh_key_file"; then
          success=$((success + 1))
        fi
      done
      echo ""
      echo "Dev nodes: $success/$total successful"
      ;;
    
    *)
      echo "[!] Invalid stage: $stage (expected 2 or 3)"
      exit 1
      ;;
  esac
  
  echo ""
  echo "================================================================================"
  echo "DEPLOYMENT COMPLETE"
  echo "================================================================================"
}

# Parse arguments
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <2|3>"
  echo "  Stage 2: Deploy worker sync scripts to worker nodes"
  echo "  Stage 3: Deploy dev push scripts to dev nodes"
  exit 1
fi

main "$1"
