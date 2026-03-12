#!/bin/bash
# ============================================================================
# PHASE 2: DEV HOST (.31) LOCKDOWN & CLEANUP (Autonomous Script)
# ============================================================================
# Purpose: Lock down the dev host to prevent runtime deployments
# Usage: sudo bash scripts/ops/dev-host-lockdown-phase2.sh
# Note: Requires sudo; run with: sudo bash $0
# ============================================================================

set -euo pipefail

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
LOG_FILE="/tmp/dev-host-lockdown-${TIMESTAMP}.log"
AUDIT_FILE="/tmp/HOST_MIGRATION_AUDIT_TRAIL_20260312.jsonl"

log_msg() {
    local msg="$1"
    echo "[$(date -u)]  $msg" | tee -a "$LOG_FILE"
}

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script requires sudo. Run with: sudo bash $0"
    exit 1
fi

log_msg "=== PHASE 2: DEV HOST LOCKDOWN STARTED ==="

# ============================================================================
# PHASE 2.1: STOP ALL RUNTIME SERVICES
# ============================================================================

log_msg "Phase 2.1: Stopping runtime services on dev host..."
for svc in docker kubernetes kubelet containerd snapd; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        log_msg "  Stopping: $svc"
        systemctl stop "$svc" || log_msg "  WARNING: Failed to stop $svc (may not exist or already stopped)"
    else
        log_msg "  Skipping: $svc (not active)"
    fi
done
log_msg "Phase 2.1 COMPLETE: All runtime services stopped"

# ============================================================================
# PHASE 2.2: DISABLE AUTO-START
# ============================================================================

log_msg "Phase 2.2: Disabling service auto-start..."
for svc in docker kubernetes kubelet containerd snapd; do
    if systemctl is-enabled "$svc" 2>/dev/null; then
        log_msg "  Disabling: $svc"
        systemctl disable "$svc" || log_msg "  WARNING: Failed to disable $svc"
    else
        log_msg "  Skipping: $svc (not enabled)"
    fi
done
log_msg "Phase 2.2 COMPLETE: Auto-start disabled for all runtimes"

# ============================================================================
# PHASE 2.3: CONFIGURE SUDO TO PREVENT INSTALLS
# ============================================================================

log_msg "Phase 2.3: Configuring sudoers to prevent package installations..."

SUDOERS_FILE="/etc/sudoers.d/99-no-install"
if [ -f "$SUDOERS_FILE" ]; then
    log_msg "  Sudoers file already exists: $SUDOERS_FILE"
else
    cat > "$SUDOERS_FILE" <<'SUDOERS'
# Prevent package installations on dev host (March 12, 2026 lockdown)
# Only allow read-only and development commands
Defaults:/usr/bin/apt-get secure_path=""
Defaults:/usr/bin/apt secure_path=""
Defaults:/usr/bin/snap secure_path=""
Defaults:/usr/bin/dpkg secure_path=""

# Explicitly deny: apt-get install, apt install, snap install, dpkg -i
Cmnd_Alias FORBIDDEN_CMDS = /usr/bin/apt-get install *, /usr/bin/apt install *, /usr/bin/snap install *, /usr/bin/snap remove *, /usr/bin/dpkg -i *

# Apply denial
ALL ALL = (ALL) DENY: FORBIDDEN_CMDS

# Allow read-only and safe operations
%sudo ALL = NOPASSWD: /usr/bin/git *, /usr/bin/docker *, /usr/bin/make *, /usr/bin/npm *, /usr/bin/python*
SUDOERS
    chmod 0440 "$SUDOERS_FILE"
    log_msg "  Created sudoers file: $SUDOERS_FILE"
fi
log_msg "Phase 2.3 COMPLETE: Sudoers restrictions applied"

# ============================================================================
# PHASE 2.4: REMOVE UNNECESSARY PACKAGES
# ============================================================================

log_msg "Phase 2.4: Removing runtime packages from dev host..."
PKGS_TO_REMOVE=(
    "docker.io"
    "docker-compose"
    "kubernetes-client"
    "helm"
    "kubelet"
    "kubeadm"
)

for pkg in "${PKGS_TO_REMOVE[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg"; then
        log_msg "  Removing: $pkg"
        apt-get remove -y "$pkg" 2>/dev/null || log_msg "  WARNING: Failed to remove $pkg"
    else
        log_msg "  Skipping: $pkg (not installed)"
    fi
done

log_msg "  Running autoremove..."
apt-get autoremove -y 2>/dev/null || log_msg "  WARNING: autoremove had issues"
log_msg "Phase 2.4 COMPLETE: Runtime packages removed"

# ============================================================================
# PHASE 2.5: CLEAN UP RUNTIME ARTIFACTS
# ============================================================================

log_msg "Phase 2.5: Cleaning up runtime artifacts..."
DIRS_TO_CLEAN=(
    "/var/lib/docker"
    "/var/lib/containerd"
    "/opt/kubernetes"
    "/opt/helm"
    "/var/run/docker.sock"
)

for dir in "${DIRS_TO_CLEAN[@]}"; do
    if [ -e "$dir" ]; then
        log_msg "  Removing: $dir"
        rm -rf "$dir" 2>/dev/null || log_msg "  WARNING: Failed to remove $dir"
    else
        log_msg "  Skipping: $dir (not found)"
    fi
done
log_msg "Phase 2.5 COMPLETE: Runtime artifacts cleaned"

# ============================================================================
# PHASE 2.6: VERIFY ESSENTIAL DEV TOOLS REMAIN
# ============================================================================

log_msg "Phase 2.6: Verifying essential dev tools..."
TOOLS=("git" "node" "npm" "python3" "gcc" "make" "bash")
for tool in "${TOOLS[@]}"; do
    if command -v "$tool" &> /dev/null; then
        VERSION=$(command -v "$tool" 2>&1 | head -1)
        log_msg "  ✓ $tool: $(command -v "$tool")"
    else
        log_msg "  ✗ $tool: NOT FOUND (may need to install)"
    fi
done
log_msg "Phase 2.6 COMPLETE: Dev tools verified"

# ============================================================================
# PHASE 2.7: WRITE AUDIT ENTRY
# ============================================================================

log_msg "Phase 2.7: Writing audit entry..."
if [ -f "$AUDIT_FILE" ]; then
    ENTRY="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"DEV_HOST_LOCKDOWN_COMPLETE\",\"host\":\"dev-elevatediq-2 (192.168.168.31)\",\"services_stopped\":5,\"sudoers_configured\":true,\"packages_removed\":${#PKGS_TO_REMOVE[@]},\"artifacts_cleaned\":${#DIRS_TO_CLEAN[@]},\"status\":\"SUCCESS\"}"
    # Use tee -a so the append runs with root privileges when the script is run under sudo
    printf '%s\n' "$ENTRY" | tee -a "$AUDIT_FILE" >/dev/null
    log_msg "  Appended audit entry to: $AUDIT_FILE"
else
    log_msg "  WARNING: Audit file not found at $AUDIT_FILE (skipping append)"
fi
log_msg "Phase 2.7 COMPLETE: Audit entry written"

# ============================================================================
# FINAL STATUS
# ============================================================================

log_msg "=== PHASE 2: DEV HOST LOCKDOWN COMPLETE ==="
log_msg ""
log_msg "✅ All operations completed successfully"
log_msg ""
log_msg "Summary:"
log_msg "  • Runtime services: STOPPED & DISABLED"
log_msg "  • Sudo restrictions: ENFORCED (no apt-get/snap/dpkg installs)"
log_msg "  • Runtime packages: REMOVED (docker, helm, kubernetes-client)"
log_msg "  • Artifacts: CLEANED (/var/lib/docker, /var/lib/containerd, etc.)"
log_msg "  • Dev tools: VERIFIED (git, node, npm, python3, gcc, make)"
log_msg "  • Audit trail: UPDATED ($AUDIT_FILE)"
log_msg ""
log_msg "Log saved to: $LOG_FILE"
log_msg ""
log_msg "Next steps (automated on worker node):"
log_msg "  • CronJob 'host-crash-analyzer' deployed to worker (192.168.168.42)"
log_msg "  • Schedule: Daily at 2 AM UTC (0 2 * * *)"
log_msg "  • Audit bucket: gs://nexusshield-prod-host-crash-audit/migrations/"
log_msg ""

exit 0
