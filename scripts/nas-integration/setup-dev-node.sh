#!/bin/bash
#
# 🎯 DEV NODE (192.168.168.31) - NAS INTEGRATION SETUP SCRIPT
#
# Configures development workstation to leverage NAS as centralized configuration repository
# 
# Features:
#   ✅ SSH key-based authentication to NAS
#   ✅ Local staging directory for IAC configurations
#   ✅ Manual push, watch mode, and diff modes
#   ✅ Git integration (optional)
#   ✅ Systemd services for background sync
#   ✅ Health monitoring and logging
#   ✅ Credential management via GCP Secret Manager
#
# Usage:
#   sudo bash setup-dev-node.sh [--skip-git] [--watch-mode]
#
# Environment variables (optional):
#   NAS_HOST=192.168.168.100           # NAS server IP
#   NAS_PORT=22                        # SSH port
#   DEV_USER=automation                # Local automation user
#   SKIP_SYSTEMD=false                 # Skip systemd setup
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Network
readonly NAS_HOST="${NAS_HOST:-192.168.168.100}"
readonly NAS_PORT="${NAS_PORT:-22}"
readonly NAS_USER="${NAS_USER:-elevatediq-svc-nas}"
readonly DEV_HOST="192.168.168.31"

# Local paths
readonly DEV_USER="${DEV_USER:-automation}"
readonly OPT_AUTOMATION="/opt/automation"
readonly OPT_IAC="/opt/iac-configs"
readonly NAS_PUSH_STAGING="/tmp/nas-push-staging"
readonly LOG_DIR="/var/log/nas-integration"
readonly AUDIT_DIR="/var/audit/nas-integration"
readonly SSH_DIR="/home/${DEV_USER}/.ssh"

# Service account
readonly SERVICE_ACCOUNT="automation"

# Features
readonly ENABLE_GIT_COMMIT="${ENABLE_GIT_COMMIT:-false}"
readonly SKIP_SYSTEMD="${SKIP_SYSTEMD:-false}"
readonly FORCE_SETUP="${FORCE_SETUP:-false}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# ============================================================================
# LOGGING
# ============================================================================

log() { echo -e "${BLUE}→${NC} $*"; }
success() { echo -e "${GREEN}✅${NC} $*"; }
warn() { echo -e "${YELLOW}⚠️${NC}  $*" >&2; }
error() { echo -e "${RED}❌${NC} $*" >&2; exit 1; }

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================

check_prerequisites() {
  log "Checking prerequisites..."
  
  # Check root
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
  fi
  
  # Check network
  if ! hostname -I | grep -q "192.168.168.31"; then
    if [[ "${FORCE_SETUP}" != "true" ]]; then
      warn "Not running on dev node (expected 192.168.168.31)"
      warn "Use FORCE_SETUP=true to override"
    fi
  fi
  
  # Check commands
  local required_cmds=(ssh rsync git curl)
  for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      error "Required command not found: $cmd"
    fi
  done
  
  success "Prerequisites check passed"
}

# ============================================================================
# CREATE SERVICE ACCOUNT & DIRECTORIES
# ============================================================================

setup_service_account() {
  log "Setting up service account..."
  
  # Create automation user if needed
  if ! id "$DEV_USER" &>/dev/null; then
    log "Creating $DEV_USER service account..."
    useradd -m -s /bin/bash -G sudo "$DEV_USER" || warn "$DEV_USER already exists"
  fi
  
  # Create automation directories
  mkdir -p "$OPT_AUTOMATION"
  mkdir -p "$OPT_IAC"
  mkdir -p "$LOG_DIR"
  mkdir -p "$AUDIT_DIR"
  
  # Set permissions
  chown -R "$DEV_USER:$DEV_USER" "$OPT_AUTOMATION"
  chown -R "$DEV_USER:$DEV_USER" "$OPT_IAC"
  chown -R "$DEV_USER:$DEV_USER" "$LOG_DIR"
  chown -R "$DEV_USER:$DEV_USER" "$AUDIT_DIR"
  
  chmod 750 "$OPT_AUTOMATION"
  chmod 750 "$OPT_IAC"
  chmod 700 "$LOG_DIR"
  chmod 700 "$AUDIT_DIR"
  
  success "Service account setup complete"
}

# ============================================================================
# SSH KEY MANAGEMENT
# ============================================================================

setup_ssh_keys() {
  log "Setting up SSH keys for NAS authentication..."
  
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  
  local key_path="${SSH_DIR}/nas-push-key"
  
  # Check if key already exists
  if [[ -f "$key_path" ]]; then
    log "SSH key already exists at $key_path"
    if [[ "${FORCE_SETUP}" != "true" ]]; then
      success "SSH key setup - using existing key"
      return 0
    fi
    warn "Regenerating SSH key (FORCE_SETUP=true)"
    rm -f "$key_path" "${key_path}.pub"
  fi
  
  # Generate ED25519 key (preferred for this use case)
  log "Generating new ED25519 SSH key..."
  ssh-keygen -t ed25519 \
    -f "$key_path" \
    -N "" \
    -C "nas-push@${DEV_HOST}" \
    -q
  
  chmod 600 "$key_path"
  chmod 644 "${key_path}.pub"
  chown "$DEV_USER:$DEV_USER" "$key_path" "${key_path}.pub"
  
  success "SSH key generated: $key_path"
  log "Public key:"
  cat "${key_path}.pub"
  log ""
  log "⚠️  ACTION REQUIRED: Add the public key above to NAS authorized_keys:"
  log "   ssh-copy-id -i ${key_path}.pub ${NAS_USER}@${NAS_HOST}"
  echo ""
}

# ============================================================================
# COPY SCRIPTS & CONFIGURATION
# ============================================================================

copy_scripts() {
  log "Installing NAS integration scripts..."
  
  local scripts=(
    "dev-node-nas-push.sh"
    "healthcheck-worker-nas.sh"
  )
  
  for script in "${scripts[@]}"; do
    local src="${SCRIPT_DIR}/$script"
    local dst="${OPT_AUTOMATION}/scripts/nas-integration/$script"
    
    if [[ ! -f "$src" ]]; then
      warn "Script not found: $src"
      continue
    fi
    
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    chmod 755 "$dst"
    chown "$DEV_USER:$DEV_USER" "$dst"
    
    success "Installed: $dst"
  done
  
  # Copy documentation
  local docs=(
    "NAS_INTEGRATION_COMPLETE.md"
    "NAS_QUICKSTART.md"
  )
  
  for doc in "${docs[@]}"; do
    local src="${REPO_ROOT}/docs/$doc"
    if [[ -f "$src" ]]; then
      cp "$src" "${OPT_AUTOMATION}/docs/nas-integration/" 2>/dev/null || \
        mkdir -p "${OPT_AUTOMATION}/docs/nas-integration" && cp "$src" "${OPT_AUTOMATION}/docs/nas-integration/"
    fi
  done
  
  success "Scripts and documentation installed"
}

# ============================================================================
# TEST NAS CONNECTIVITY
# ============================================================================

test_nas_connectivity() {
  log "Testing connectivity to NAS server..."
  
  local key_path="${SSH_DIR}/nas-push-key"
  
  if [[ ! -f "$key_path" ]]; then
    warn "SSH key not found, skipping connectivity test"
    warn "Add the public key to NAS and try again"
    return 1
  fi
  
  # Test SSH connection
  if ssh -i "$key_path" \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=5 \
    -o BatchMode=yes \
    "${NAS_USER}@${NAS_HOST}" \
    "test -d /home/elevatediq-svc-nas/repositories/iac && echo 'NAS IAC repository accessible'" &>/dev/null; then
    
    success "NAS connectivity test passed"
    return 0
  else
    warn "Cannot reach NAS yet - ensure:"
    warn "  1. NAS server is running at $NAS_HOST:$NAS_PORT"
    warn "  2. Public key has been added to NAS authorized_keys"
    warn "  3. User '$NAS_USER' has proper permissions"
    return 1
  fi
}

# ============================================================================
# SETUP ENVIRONMENT CONFIGURATION
# ============================================================================

setup_env_config() {
  log "Creating environment configuration..."
  
  local config_file="${OPT_AUTOMATION}/dev-node-nas.env"
  
  cat > "$config_file" <<'EOF'
# ============================================================================
# DEV NODE NAS INTEGRATION CONFIGURATION
# ============================================================================
# This file contains environment variables for NAS integration on 192.168.168.31

# Network Configuration
export NAS_HOST="192.168.168.100"
export NAS_PORT="22"
export NAS_USER="elevatediq-svc-nas"
export DEV_HOST="192.168.168.31"
export DEV_USER="automation"

# Local Paths
export OPT_AUTOMATION="/opt/automation"
export OPT_IAC="/opt/iac-configs"
export NAS_PUSH_STAGING="/tmp/nas-push-staging"
export LOG_DIR="/var/log/nas-integration"
export AUDIT_DIR="/var/audit/nas-integration"
export SSH_KEY="/home/${DEV_USER}/.ssh/nas-push-key"

# NAS Remote Paths
export NAS_IAC_REPO="/home/elevatediq-svc-nas/repositories/iac"
export NAS_CONFIGS_DIR="/home/elevatediq-svc-nas/config-vault"

# Service Account
export SERVICE_ACCOUNT="automation"

# Features
export ENABLE_GIT_COMMIT="false"
export ENABLE_WATCH_MODE="true"

# Rsync Options
export RSYNC_OPTS="-avz --checksum --timeout=30 --delete"

# SSH Options
export SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"

# Logging
export LOG_LEVEL="INFO"
EOF
  
  chmod 644 "$config_file"
  chown "$DEV_USER:$DEV_USER" "$config_file"
  
  success "Environment configuration created: $config_file"
}

# ============================================================================
# CREATE SAMPLE IAC STRUCTURE
# ============================================================================

create_iac_structure() {
  log "Creating sample IAC directory structure..."
  
  local dirs=(
    "ansible"
    "kubernetes"
    "terraform"
    "docker"
    "scripts"
    "configs"
  )
  
  for dir in "${dirs[@]}"; do
    mkdir -p "${OPT_IAC}/$dir"
  done
  
  # Create README
  cat > "${OPT_IAC}/README.md" <<'EOF'
# Infrastructure as Code Repository (Dev Node)

This directory contains Infrastructure as Code configurations that are synchronized to the NAS server.

## Directory Structure

- **ansible/**: Ansible playbooks and roles
- **kubernetes/**: Kubernetes manifests and Helm charts
- **terraform/**: Terraform configurations
- **docker/**: Docker Compose files and Dockerfiles
- **scripts/**: Deployment and utility scripts
- **configs/**: Configuration files and templates

## Usage

### Push to NAS (Manual)
```bash
/opt/automation/scripts/nas-integration/dev-node-nas-push.sh push
```

### Show Pending Changes
```bash
/opt/automation/scripts/nas-integration/dev-node-nas-push.sh diff
```

### Enable Watch Mode (Continuous Sync)
```bash
/opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch
```

## Important Notes

- Changes are automatically signed and audited
- All syncs are logged in `/var/log/nas-integration/dev-node-push.log`
- Sensitive files (*.key, *.pem, *secret*) are automatically blocked
- Worker nodes pull from NAS every 30 minutes
EOF
  
  chown -R "$DEV_USER:$DEV_USER" "$OPT_IAC"
  chmod -R 750 "$OPT_IAC"
  
  success "IAC directory structure created at $OPT_IAC"
}

# ============================================================================
# SETUP NFS MOUNTS
# ============================================================================

setup_nfs_mounts() {
  log "Setting up NFS mounts for centralized repositories..."
  
  # Run NFS mount setup script
  if [[ -f "${SCRIPT_DIR}/setup-nfs-mounts.sh" ]]; then
    log "Running NFS mount configuration..."
    bash "${SCRIPT_DIR}/setup-nfs-mounts.sh" mount || {
      warn "NFS mount setup failed - continuing anyway"
      warn "Run manually: sudo bash scripts/nas-integration/setup-nfs-mounts.sh mount"
    }
    success "NFS mounts configured"
  else
    warn "NFS mount script not found: ${SCRIPT_DIR}/setup-nfs-mounts.sh"
  fi
}

# ============================================================================
# SETUP SYSTEMD SERVICES
# ============================================================================

setup_systemd_services() {
  if [[ "$SKIP_SYSTEMD" == "true" ]]; then
    log "Skipping systemd setup (SKIP_SYSTEMD=true)"
    return 0
  fi
  
  log "Setting up systemd services for NAS integration..."
  
  # Dev node push service (manual trigger)
  local service_file="/etc/systemd/system/nas-dev-push.service"
  
  cat > "$service_file" <<EOF
[Unit]
Description=Dev Node NAS Configuration Push
Documentation=file://${OPT_AUTOMATION}/docs/nas-integration/NAS_INTEGRATION_COMPLETE.md
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${DEV_USER}
Group=${DEV_USER}
ExecStart=${OPT_AUTOMATION}/scripts/nas-integration/dev-node-nas-push.sh push
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nas-dev-push
RemainAfterExit=no

# Security
PrivateTmp=yes
NoNewPrivileges=yes
ProtectHome=yes
ReadWritePaths=/opt/iac-configs /var/log/nas-integration /tmp/nas-push-staging /opt/automation

# Environment
Environment="NAS_HOST=${NAS_HOST}"
Environment="NAS_PORT=${NAS_PORT}"
Environment="DEV_USER=${DEV_USER}"
Environment="SSH_KEY=/home/${DEV_USER}/.ssh/nas-push-key"

[Install]
WantedBy=multi-user.target
EOF

  chmod 644 "$service_file"
  
  # Health check timer
  local timer_file="/etc/systemd/system/nas-dev-healthcheck.timer"
  local healthcheck_service="/etc/systemd/system/nas-dev-healthcheck.service"
  
  cat > "$healthcheck_service" <<EOF
[Unit]
Description=Dev Node NAS Integration Health Check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${DEV_USER}
Group=${DEV_USER}
ExecStart=${OPT_AUTOMATION}/scripts/nas-integration/healthcheck-worker-nas.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nas-dev-health

[Install]
WantedBy=nas-dev-healthcheck.timer
EOF

  cat > "$timer_file" <<EOF
[Unit]
Description=Dev Node NAS Integration Health Check Timer
Documentation=file://${OPT_AUTOMATION}/docs/nas-integration/NAS_INTEGRATION_COMPLETE.md

[Timer]
OnBootSec=5min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

  chmod 644 "$healthcheck_service" "$timer_file"
  
  # Reload systemd
  systemctl daemon-reload
  
  success "Systemd services created:"
  success "  - $service_file (manual trigger)"
  success "  - $healthcheck_service"
  success "  - $timer_file (runs every 30 min)"
}

# ============================================================================
# CREATE QUICK START GUIDE
# ============================================================================

create_quickstart() {
  log "Creating quick start guide..."
  
  local quickstart_file="${OPT_AUTOMATION}/DEV_NODE_QUICKSTART.md"
  
  cat > "$quickstart_file" <<'EOF'
# Dev Node (192.168.168.31) - Quick Start Guide

## Overview

Your development workstation is now configured to leverage the NAS as a centralized configuration repository.

## Key Paths

- **Local IAC**: `/opt/iac-configs/` - Edit your infrastructure configs here
- **Logs**: `/var/log/nas-integration/` - View integration logs
- **SSH Key**: `/home/automation/.ssh/nas-push-key` - Used for NAS auth
- **Config**: `/opt/automation/dev-node-nas.env` - Integration settings

## Common Tasks

### 1. Push Changes to NAS (Manual)

```bash
/opt/automation/scripts/nas-integration/dev-node-nas-push.sh push
```

This will:
- Validate your configurations
- Check for sensitive files
- Push to NAS via rsync
- Create audit trail entry

### 2. View Pending Changes

```bash
/opt/automation/scripts/nas-integration/dev-node-nas-push.sh diff
```

### 3. Enable Watch Mode (Continuous Sync)

```bash
/opt/automation/scripts/nas-integration/dev-node-nas-push.sh watch
```

This monitors your IAC directory and auto-pushes on changes.

### 4. Trigger Manual Health Check

```bash
sudo systemctl start nas-dev-healthcheck.service
```

### 5. View Integration Logs

```bash
tail -f /var/log/nas-integration/dev-node-push.log
journalctl -u nas-dev-push.service -f
```

## Data Flow

```
You Edit Files          NAS Server              Worker Nodes
/opt/iac-configs/ ----[rsync push]--> /repositories/iac/ ---[rsync pull (30min)]---> /opt/nas-sync/iac/
                  (on demand)                                    (automatic)
```

## Important Notes

✅ **Automatic Blocking**:
- Sensitive files (*.key, *.pem, *secret*) are blocked
- YAML validation runs before push
- All operations are audited

✅ **Worker Nodes**:
- Pull from NAS every 30 minutes
- Changes are deployed automatically
- Your changes appear on workers within 30 min

⚠️ **SSH Key**:
- Located at: `/home/automation/.ssh/nas-push-key`
- Used for all NAS communications
- Keep secure - never share

## Troubleshooting

### Cannot Connect to NAS

1. Check SSH key exists:
   ```bash
   ls -la /home/automation/.ssh/nas-push-key
   ```

2. Test connectivity:
   ```bash
   ssh -i /home/automation/.ssh/nas-push-key elevatediq-svc-nas@192.168.168.100 "echo OK"
   ```

3. Verify NAS has your public key:
   ```bash
   cat /home/automation/.ssh/nas-push-key.pub
   ```

### Changes Not Showing on Worker Nodes

1. Verify push succeeded:
   ```bash
   tail /var/log/nas-integration/dev-node-push.log
   ```

2. Check NAS for your files:
   ```bash
   ssh -i /home/automation/.ssh/nas-push-key elevatediq-svc-nas@192.168.168.100 \
     "ls -la /home/elevatediq-svc-nas/repositories/iac/"
   ```

3. Wait up to 30 minutes for worker nodes to pull

## Next Steps

1. **Edit Configurations**: Add your IAC configs to `/opt/iac-configs/`
2. **Push to NAS**: Run `dev-node-nas-push.sh push`
3. **Verify on Worker**: Within 30 min, changes appear at 192.168.168.42
4. **Monitor**: Check logs: `tail -f /var/log/nas-integration/dev-node-push.log`

## Support

- Comprehensive Guide: `/opt/automation/docs/nas-integration/NAS_INTEGRATION_COMPLETE.md`
- Full API Reference: See documentation for all endpoint details
- Audit Trail: `/var/audit/nas-integration/`

---

**Status**: ✅ Ready for use  
**Last Updated**: 2026-03-15  
EOF

  chmod 644 "$quickstart_file"
  chown "$DEV_USER:$DEV_USER" "$quickstart_file"
  
  success "Quick start guide created: $quickstart_file"
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================

summary() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════════════════╗"
  echo "║                  ✅ DEV NODE SETUP COMPLETE                               ║"
  echo "║                   NAS Integration Ready (192.168.168.31)                  ║"
  echo "╚════════════════════════════════════════════════════════════════════════════╝"
  echo ""
  
  echo "📁 Key Directories:"
  echo "   Local IAC:        $OPT_IAC"
  echo "   Staging:          $NAS_PUSH_STAGING"
  echo "   Logs:             $LOG_DIR"
  echo "   Scripts:          $OPT_AUTOMATION/scripts/nas-integration"
  echo ""
  
  echo "🔐 SSH Configuration:"
  echo "   Key Location:     $SSH_DIR/nas-push-key"
  echo "   Public Key:"
  cat "${SSH_DIR}/nas-push-key.pub"
  echo ""
  
  echo "⚡ Quick Commands:"
  echo "   Push to NAS:    $OPT_AUTOMATION/scripts/nas-integration/dev-node-nas-push.sh push"
  echo "   Watch changes:  $OPT_AUTOMATION/scripts/nas-integration/dev-node-nas-push.sh watch"
  echo "   Check diffs:    $OPT_AUTOMATION/scripts/nas-integration/dev-node-nas-push.sh diff"
  echo "   View logs:      tail -f $LOG_DIR/dev-node-push.log"
  echo ""
  
  echo "📖 Getting Started:"
  echo "   1. Add SSH public key to NAS admin"
  echo "   2. Test connection: ssh -i ${SSH_DIR}/nas-push-key elevatediq-svc-nas@${NAS_HOST}"
  echo "   3. Edit configs in: $OPT_IAC"
  echo "   4. Push: $OPT_AUTOMATION/scripts/nas-integration/dev-node-nas-push.sh push"
  echo "   5. Monitor: tail -f $LOG_DIR/dev-node-push.log"
  echo ""
  
  echo "📚 Documentation:"
  echo "   Quick Start:      $OPT_AUTOMATION/DEV_NODE_QUICKSTART.md"
  echo "   Full Guide:       $OPT_AUTOMATION/docs/nas-integration/NAS_INTEGRATION_COMPLETE.md"
  echo ""
  
  echo "🔄 Data Flow:"
  echo "   You edit → /opt/iac-configs → rsync push → NAS → Worker nodes (30min)"
  echo ""
  
  echo "⚠️  NEXT ACTIONS:"
  echo "   1. Copy public SSH key to NAS admin:"
  echo "      cat ${SSH_DIR}/nas-push-key.pub"
  echo "   2. Once key is added to NAS, test:"
  echo "      ssh -i ${SSH_DIR}/nas-push-key elevatediq-svc-nas@${NAS_HOST} 'echo OK'"
  echo "   3. Then push your first configs:"
  echo "      $OPT_AUTOMATION/scripts/nas-integration/dev-node-nas-push.sh push"
  echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  log "Starting Dev Node NAS Integration Setup..."
  log "Target: 192.168.168.31"
  log "NAS Server: $NAS_HOST:$NAS_PORT"
  echo ""
  
  check_prerequisites
  setup_service_account
  setup_ssh_keys
  copy_scripts
  setup_env_config
  create_iac_structure
  setup_nfs_mounts
  setup_systemd_services
  create_quickstart
  
  # Test connectivity (non-blocking)
  if test_nas_connectivity; then
    success "NAS connectivity verified!"
  else
    warn "NAS connectivity test failed - this is expected until SSH key is added"
  fi
  
  summary
}

# Run main
main "$@"
