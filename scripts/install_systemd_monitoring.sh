#!/bin/bash
# Install and enable service account monitoring timers
# This script installs systemd services and timers for automated health checks and credential rotation

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"
SYSTEMD_SOURCE_DIR="$WORKSPACE_ROOT/systemd"
SYSTEMD_TARGET_DIR="/etc/systemd/system"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

check_availability() {
    log_info "Checking installation availability..."
    
    # Check if running with sudo
    if [ "$EUID" -ne 0 ]; then
        log_warn "Not running as root - attempting user-level installation"
        INSTALL_MODE="user"
        SYSTEMD_TARGET_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SYSTEMD_TARGET_DIR"
        return 0
    fi
    
    INSTALL_MODE="system"
    log_success "Running with sudo - system-level installation"
}

install_services() {
    log_info "Installing systemd services and timers..."
    
    local files_installed=0
    
    # Copy service-account specific files only
    for file in "$SYSTEMD_SOURCE_DIR"/service-account*.service "$SYSTEMD_SOURCE_DIR"/service-account*.timer; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            log_info "Installing: $filename"
            
            if [ "$INSTALL_MODE" = "system" ]; then
                sudo cp "$file" "$SYSTEMD_TARGET_DIR/" 2>/dev/null || cp "$file" "$SYSTEMD_TARGET_DIR/" 2>/dev/null
                [ -f "$SYSTEMD_TARGET_DIR/$filename" ] && log_success "Installed: $filename" || log_warn "Could not install: $filename"
            else
                mkdir -p "$SYSTEMD_TARGET_DIR"
                cp "$file" "$SYSTEMD_TARGET_DIR/" 2>/dev/null
                [ -f "$SYSTEMD_TARGET_DIR/$filename" ] && log_success "Installed: $filename" || log_warn "Could not install: $filename"
            fi
            
            ((files_installed++))
        fi
    done
    
    log_success "Installed $files_installed service-account files"
}

reload_systemd() {
    log_info "Reloading systemd configuration..."
    
    if [ "$INSTALL_MODE" = "system" ]; then
        sudo systemctl daemon-reload
        log_success "systemd reloaded (system-wide)"
    else
        systemctl --user daemon-reload
        log_success "systemd reloaded (user)"
    fi
}

enable_timers() {
    log_info "Enabling timers..."
    
    local timers=(
        "service-account-health-check.timer"
        "service-account-credential-rotation.timer"
    )
    
    for timer in "${timers[@]}"; do
        log_info "Enabling: $timer"
        
        if [ "$INSTALL_MODE" = "system" ]; then
            sudo systemctl enable "$timer"
            sudo systemctl start "$timer" || log_warn "Could not start $timer (may start on schedule)"
        else
            systemctl --user enable "$timer"
            systemctl --user start "$timer" || log_warn "Could not start $timer (may start on schedule)"
        fi
        
        log_success "Enabled: $timer"
    done
}

verify_installation() {
    log_info "Verifying installation..."
    
    if [ "$INSTALL_MODE" = "system" ]; then
        sudo systemctl status service-account-health-check.timer --no-pager || true
        sudo systemctl status service-account-credential-rotation.timer --no-pager || true
    else
        systemctl --user status service-account-health-check.timer --no-pager || true
        systemctl --user status service-account-credential-rotation.timer --no-pager || true
    fi
    
    log_success "Installation complete"
}

main() {
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║   Service Account Monitoring Installation   ║"
    echo "╚════════════════════════════════════════════╝"
    echo ""
    
    check_availability
    install_services
    reload_systemd
    enable_timers
    verify_installation
    
    echo ""
    echo "✅ Service account monitoring enabled!"
    echo ""
    echo "Installed timers:"
    echo "  • service-account-health-check.timer (hourly)"
    echo "  • service-account-credential-rotation.timer (monthly)"
    echo ""
    echo "View timer status:"
    if [ "$INSTALL_MODE" = "system" ]; then
        echo "  systemctl status service-account-health-check.timer"
        echo "  systemctl status service-account-credential-rotation.timer"
    else
        echo "  systemctl --user status service-account-health-check.timer"
        echo "  systemctl --user status service-account-credential-rotation.timer"
    fi
    echo ""
}

main "$@"
