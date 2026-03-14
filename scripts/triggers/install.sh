#!/bin/bash
################################################################################
# ⚡ INSTALLATION & SETUP SCRIPT
# 
# Automated Deployment Trigger System Setup
# 
# This script configures the entire automated deployment system:
#   1. Git hooks installation (local development)
#   2. Post-receive hook setup (remote server)
#   3. Webhook handler integration
#   4. Environment configuration
#   5. Slack notification setup
#   6. Verification tests
#
# Usage:
#   bash scripts/triggers/install.sh                    # Full setup
#   bash scripts/triggers/install.sh --local-only      # Git hooks only
#   bash scripts/triggers/install.sh --remote-setup    # Server-side only
#   bash scripts/triggers/install.sh --webhook-only    # Webhook integration
#
# Modes:
#   full       - Complete setup (default)
#   local      - Git hooks and local configuration
#   remote     - Post-receive hook on server
#   webhook    - GitHub webhook integration
#   verify     - Test the installation
#
################################################################################

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SETUP_MODE="${1:-full}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_step() { echo -e "${YELLOW}▶${NC} $*"; }

# ============================================================================
# LOCAL GIT HOOKS SETUP
# ============================================================================

setup_local_git_hooks() {
    log_step "Setting up local Git hooks"
    
    # Configure git to use .githooks directory
    if git config core.hooksPath .githooks >/dev/null 2>&1; then
        log_success "Git hooks path configured: .githooks"
    else
        log_error "Failed to configure git hooks path"
        return 1
    fi
    
    # Verify hooks are in place
    if [[ ! -f "$REPO_ROOT/.githooks/post-push" ]]; then
        log_error "post-push hook not found"
        return 1
    fi
    
    if [[ ! -x "$REPO_ROOT/.githooks/post-push" ]]; then
        log_step "Making post-push hook executable"
        chmod +x "$REPO_ROOT/.githooks/post-push"
    fi
    
    log_success "Local Git hooks configured"
    log_info "When you push to main, deployment will automatically trigger"
    
    return 0
}

# ============================================================================
# REMOTE POST-RECEIVE SETUP
# ============================================================================

setup_remote_post_receive() {
    local target_host="${TARGET_HOST:-192.168.168.42}"
    local service_account="${SERVICE_ACCOUNT:-automation}"
    local ssh_key="${SSH_KEY:-$HOME/.ssh/automation_ed25519}"
    
    log_step "Setting up post-receive hook on remote server"
    log_info "Target: ${service_account}@${target_host}"
    
    # Verify SSH connectivity
    if ! ssh -i "$ssh_key" -o ConnectTimeout=5 "${service_account}@${target_host}" "echo 'SSH connection verified'" 2>/dev/null; then
        log_error "Cannot connect to target host: $target_host"
        log_info "Please verify:"
        log_info "  1. Target host is running: $target_host"
        log_info "  2. SSH key is correct: $ssh_key"
        log_info "  3. Service account has access: $service_account"
        return 1
    fi
    
    log_success "SSH connection verified"
    
    # Copy hook script to remote
    log_step "Copying post-receive hook to remote server..."
    local remote_hooks_dir="/opt/self-hosted-runner/.git/hooks"
    
    if ssh -i "$ssh_key" "${service_account}@${target_host}" "test -d $remote_hooks_dir" 2>/dev/null; then
        log_info "Hooks directory exists on remote"
    else
        log_step "Creating hooks directory on remote..."
        ssh -i "$ssh_key" "${service_account}@${target_host}" "mkdir -p $remote_hooks_dir" || {
            log_error "Failed to create hooks directory on remote"
            return 1
        }
    fi
    
    # Upload and configure hook
    scp -i "$ssh_key" "$SCRIPT_DIR/post-receive-hook.sh" \
        "${service_account}@${target_host}:${remote_hooks_dir}/post-receive" || {
        log_error "Failed to copy post-receive hook to remote"
        return 1
    }
    
    ssh -i "$ssh_key" "${service_account}@${target_host}" \
        "chmod +x ${remote_hooks_dir}/post-receive" || {
        log_error "Failed to make post-receive hook executable"
        return 1
    }
    
    log_success "Post-receive hook installed on remote"
    
    return 0
}

# ============================================================================
# DEPLOYMENT TRIGGER SETUP
# ============================================================================

setup_deployment_trigger() {
    log_step "Configuring deployment trigger"
    
    # Create logs directory
    mkdir -p "$REPO_ROOT/logs/deployments"
    
    # Create backup directory
    mkdir -p "$REPO_ROOT/.deployment-backups"
    
    # Verify deployment scripts exist
    if [[ ! -x "$SCRIPT_DIR/post-push-deploy.sh" ]]; then
        log_error "Deployment trigger script not found or not executable"
        return 1
    fi
    
    log_success "Deployment trigger ready"
    log_info "Script: $(basename "$SCRIPT_DIR/post-push-deploy.sh")"
    log_info "Location: $SCRIPT_DIR/"
    
    return 0
}

# ============================================================================
# ENVIRONMENT CONFIGURATION
# ============================================================================

setup_environment() {
    log_step "Setting up environment variables"
    
    local env_file="$REPO_ROOT/.deployment.env"
    
    # Create environment file if it doesn't exist
    if [[ ! -f "$env_file" ]]; then
        log_step "Creating environment configuration file"
        
        cat > "$env_file" <<'EOF'
# Deployment Configuration
# Save as .deployment.env in repository root

# Target host for deployments
export TARGET_HOST=192.168.168.42

# Service account for SSH access
export SERVICE_ACCOUNT=automation

# SSH key for authentication
export SSH_KEY=~/.ssh/automation_ed25519

# Slack webhook for notifications (optional)
# export SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# GitHub token for status updates (optional)
# export GITHUB_TOKEN="ghp_..."

# Deployment strategy: full, smart, or tags
export DETECTION_STRATEGY=full

# Enable dry-run mode (preview without deploying)
# export DRY_RUN=true

# Disable auto-rollback on failure
# export SKIP_ROLLBACK=true

# Enable debug output
# export DEBUG=true
EOF
        
        log_success "Environment file created: $env_file"
        log_info "Edit this file to customize deployment settings"
        log_info "** IMPORTANT: Do NOT commit .deployment.env to git (contains secrets) **"
        
        # Add to .gitignore if not already there
        if ! grep -q "^.deployment.env$" "$REPO_ROOT/.gitignore" 2>/dev/null; then
            echo ".deployment.env" >> "$REPO_ROOT/.gitignore"
            log_success "Added .deployment.env to .gitignore"
        fi
    else
        log_success "Environment file already exists: $env_file"
    fi
    
    return 0
}

# ============================================================================
# SLACK INTEGRATION
# ============================================================================

setup_slack_integration() {
    log_step "Configuring Slack integration (optional)"
    
    log_info "To enable Slack notifications:"
    log_info ""
    log_info "1. Create a Slack Webhook:"
    log_info "   https://api.slack.com/apps/ → Create New App → Incoming Webhooks"
    log_info ""
    log_info "2. Add webhook URL to .deployment.env:"
    log_info "   export SLACK_WEBHOOK='https://hooks.slack.com/services/...'"
    log_info ""
    log_info "3. Test the webhook:"
    log_info "   bash scripts/triggers/test-integration.sh --slack"
    log_info ""
    
    return 0
}

# ============================================================================
# WEBHOOK INTEGRATION
# ============================================================================

setup_webhook_integration() {
    log_step "Configuring GitHub webhook integration"
    
    log_info "To enable GitHub webhooks:"
    log_info ""
    log_info "1. Repository Settings → Webhooks → Add webhook"
    log_info ""
    log_info "2. Configuration:"
    log_info "   Payload URL:     https://your-webhook-receiver.com/"
    log_info "   Content-Type:    application/json"
    log_info "   Secret:          $(openssl rand -hex 32)"
    log_info ""
    log_info "3. Events to trigger on:"
    log_info "   ✓ Pushes"
    log_info "   ✓ Pull requests"
    log_info ""
    log_info "4. Add webhook secret to deployment service:"
    log_info "   export WEBHOOK_SECRET='your-secret-here'"
    log_info ""
    
    return 0
}

# ============================================================================
# VERIFICATION & TESTING
# ============================================================================

verify_installation() {
    log_step "Verifying installation"
    
    local has_errors=0
    
    # Check local git hooks
    log_info "Checking local Git hooks..."
    if [[ -x "$REPO_ROOT/.githooks/post-push" ]]; then
        log_success "Post-push hook installed and executable"
    else
        log_error "Post-push hook missing or not executable"
        ((has_errors++))
    fi
    
    # Check deployment scripts
    log_info "Checking deployment scripts..."
    if [[ -x "$SCRIPT_DIR/post-push-deploy.sh" ]]; then
        log_success "Deploy trigger script ready"
    else
        log_error "Deployment trigger script missing or not executable"
        ((has_errors++))
    fi
    
    # Check other trigger scripts
    for script in "$SCRIPT_DIR"/*.sh; do
        if [[ -f "$script" && -x "$script" ]]; then
            log_success "Found executable: $(basename "$script")"
        fi
    done
    
    # Check logs directory
    if [[ -d "$REPO_ROOT/logs/deployments" ]]; then
        log_success "Logs directory exists"
    else
        log_info "Logs directory will be created on first deployment"
    fi
    
    # Check git configuration
    log_info "Checking Git configuration..."
    local hooks_path
    hooks_path=$(git config core.hooksPath 2>/dev/null || echo "")
    if [[ "$hooks_path" == ".githooks" ]]; then
        log_success "Git hooks path correctly configured"
    else
        log_error "Git hooks path not configured (run: git config core.hooksPath .githooks)"
        ((has_errors++))
    fi
    
    if [[ $has_errors -eq 0 ]]; then
        log_success "✅ Installation verified - system ready!"
        return 0
    else
        log_error "❌ Installation incomplete - $has_errors issues found"
        return 1
    fi
}

# ============================================================================
# MAIN INSTALLATION
# ============================================================================

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  Automated Deployment Trigger System - Installation       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_info "Repository: $REPO_ROOT"
    log_info "Setup Mode: $SETUP_MODE"
    echo ""
    
    case "$SETUP_MODE" in
        full)
            log_step "Running full installation (all components)"
            setup_local_git_hooks || exit 1
            setup_deployment_trigger || exit 1
            setup_environment || exit 1
            log_info "Remote setup requires SSH access - skipping for now"
            setup_slack_integration
            setup_webhook_integration
            echo ""
            verify_installation || exit 1
            ;;
        
        local|--local-only)
            log_step "Installing local Git hooks only"
            setup_local_git_hooks || exit 1
            verify_installation || exit 1
            ;;
        
        remote|--remote-setup)
            log_step "Installing post-receive hook on remote server"
            setup_remote_post_receive || exit 1
            ;;
        
        webhook|--webhook-only)
            log_step "Setting up webhook integration"
            setup_webhook_integration
            ;;
        
        verify)
            verify_installation || exit 1
            ;;
        
        *)
            log_error "Unknown setup mode: $SETUP_MODE"
            echo ""
            echo "Supported modes:"
            echo "  full       - Complete setup (default)"
            echo "  local      - Git hooks only"
            echo "  remote     - Post-receive hook on server"
            echo "  webhook    - Webhook integration"
            echo "  verify     - Test installation"
            exit 1
            ;;
    esac
    
    echo ""
    log_success "Setup complete!"
    echo ""
    log_info "Next Steps:"
    log_info "  1. Edit .deployment.env with your settings"
    log_info "  2. Test with: bash scripts/triggers/test-integration.sh"
    log_info "  3. Push to main branch to trigger first deployment"
    echo ""
}

# =============================================================================
# ENTRY POINT
# =============================================================================

main "$@"
