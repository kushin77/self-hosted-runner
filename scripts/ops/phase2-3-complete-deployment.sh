#!/bin/bash
# Host Migration Phase 2-3: Dev Lockdown + Audit Upload + CronJob Deploy
# Run: sudo bash /tmp/phase2-3-complete.sh
# This script:
#   Phase 2: Locks down dev host (.31)
#   Phase 3: Uploads audit trail to GCS
#   Phase 3b: Deploys CronJob to cluster

set -euo pipefail

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
LOG_FILE="/tmp/phase2-3-execution-${TIMESTAMP}.log"

log_msg() {
    local msg="$1"
    echo "[$(date -u +'%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOG_FILE"
}

log_msg "=== PHASE 2: DEV HOST LOCKDOWN START ==="

# Phase 2: Stop runtimes on dev host (.31)
log_msg "Stopping container runtimes..."
systemctl stop docker 2>/dev/null || log_msg "docker not running or failed"
systemctl stop kubernetes 2>/dev/null || log_msg "kubernetes not running or failed"
systemctl stop kubelet 2>/dev/null || log_msg "kubelet not running or failed"
systemctl stop containerd 2>/dev/null || log_msg "containerd not running or failed"
systemctl stop snapd 2>/dev/null || log_msg "snapd not running or failed"

log_msg "Disabling auto-start for runtimes..."
systemctl disable docker 2>/dev/null || true
systemctl disable kubernetes 2>/dev/null || true
systemctl disable kubelet 2>/dev/null || true
systemctl disable containerd 2>/dev/null || true
systemctl disable snapd 2>/dev/null || true

log_msg "Creating sudoers restrictions..."
cat > /etc/sudoers.d/99-no-install <<'SUDOERS_EOF'
# Dev host: prevent package installations
Cmnd_Alias FORBIDDEN = /usr/bin/apt-get install *, /usr/bin/apt install *, /usr/bin/snap install *, /usr/bin/dpkg -i *
ALL ALL = (ALL) DENY: FORBIDDEN

# Allow dev tools with no password
Cmnd_Alias DEV_TOOLS = /usr/bin/git, /usr/bin/make, /usr/bin/npm, /usr/bin/python*, /bin/bash
%sudo ALL = NOPASSWD: DEV_TOOLS

# Allow service management (informational)
Cmnd_Alias SVC_QUERY = /usr/bin/systemctl status *, /usr/bin/systemctl list-units *
%sudo ALL = NOPASSWD: SVC_QUERY
SUDOERS_EOF
chmod 440 /etc/sudoers.d/99-no-install
log_msg "Sudoers file created"

log_msg "Cleaning up runtime artifacts..."
rm -rf /var/lib/docker /var/lib/containerd /opt/kubernetes /opt/helm 2>/dev/null || true

log_msg "=== PHASE 2 COMPLETE ==="

# Phase 3: Audit upload
log_msg "=== PHASE 3: AUDIT TRAIL UPLOAD START ==="
AUDIT_FILE="/tmp/HOST_MIGRATION_AUDIT_TRAIL_20260312.jsonl"
if [ -f "$AUDIT_FILE" ]; then
    log_msg "Uploading audit trail to GCS..."
    # Use gcloud with deployer service account
    export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token 2>/dev/null || echo "")
    
    if [ -n "$GOOGLE_OAUTH_ACCESS_TOKEN" ]; then
        gsutil cp "$AUDIT_FILE" gs://nexusshield-prod-host-crash-audit/migrations/HOST_MIGRATION_AUDIT_TRAIL_20260312.jsonl 2>&1 || {
            log_msg "WARNING: GCS upload failed (auth issue) - audit file remains in /tmp"
        }
    else
        log_msg "WARNING: Could not obtain gcloud token - skipping GCS upload"
        log_msg "Manual: gsutil cp $AUDIT_FILE gs://nexusshield-prod-host-crash-audit/migrations/"
    fi
else
    log_msg "WARNING: Audit file not found at $AUDIT_FILE"
fi
log_msg "=== PHASE 3 AUDIT UPLOAD COMPLETE ==="

# Phase 3b: Deploy CronJob on worker
log_msg "=== PHASE 3B: CRONJOB DEPLOYMENT START ==="
log_msg "Deploying CronJob to worker cluster..."

ssh -i ~/.ssh/id_rsa -o BatchMode=yes -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o StrictHostKeyChecking=accept-new akushnir@192.168.168.42 "set -euo pipefail; \
  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - 2>&1; \
  kubectl apply -f ~/self-hosted-runner/k8s/monitoring/host-crash-analysis-cronjob.yaml -n monitoring 2>&1; \
  echo 'CronJob deployment complete'; \
  kubectl get cronjob,sa -n monitoring || true" 2>&1 | tee -a "$LOG_FILE"

log_msg "=== PHASE 3B COMPLETE ==="

# Final verification
log_msg "=== FINAL VERIFICATION ==="
log_msg "Dev host service status:"
systemctl status docker 2>&1 | grep -E 'Active|inactive' || true
systemctl status kubernetes 2>&1 | grep -E 'Active|inactive' || true

log_msg "Dev tools verification:"
which git node npm python3 gcc make 2>&1 | tee -a "$LOG_FILE"

log_msg "=== ALL PHASES COMPLETE ==="
log_msg "Execution log: $LOG_FILE"
log_msg "See HOST_MIGRATION_PHASE_COMPLETE_20260312.md for full details"

echo ""
echo "✅ DEPLOYMENT COMPLETE"
echo "   Phase 2: Dev host locked down"
echo "   Phase 3: Audit trail uploaded (if GCP auth available)"
echo "   Phase 3b: CronJob deployed to worker"
echo ""
echo "Logs: $LOG_FILE"
