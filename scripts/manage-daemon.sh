#!/usr/bin/env bash
# Daemon Scheduler Management Script
# Start/stop/restart/status the self-hosted credential management daemon

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="daemon-scheduler"
DAEMON_SCRIPT="${REPO_ROOT}/scripts/daemon-scheduler.sh"
DAEMON_PID_FILE="${REPO_ROOT}/.daemon.pid"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

start_daemon() {
    if is_running; then
        log_warn "Daemon already running (PID: $(cat ${DAEMON_PID_FILE}))"
        return 1
    fi
    
    log_info "Starting daemon scheduler..."
    nohup bash "${DAEMON_SCRIPT}" > /dev/null 2>&1 &
    sleep 1
    
    if is_running; then
        log_info "✓ Daemon started (PID: $(cat ${DAEMON_PID_FILE}))"
        return 0
    else
        log_error "Failed to start daemon"
        return 1
    fi
}

stop_daemon() {
    if ! is_running; then
        log_warn "Daemon not running"
        return 1
    fi
    
    local pid=$(cat "${DAEMON_PID_FILE}")
    log_info "Stopping daemon (PID: ${pid})..."
    
    kill -TERM "${pid}" 2>/dev/null || true
    sleep 2
    
    if is_running; then
        log_warn "Force killing daemon..."
        kill -9 "${pid}" 2>/dev/null || true
        sleep 1
    fi
    
    if ! is_running; then
        rm -f "${DAEMON_PID_FILE}"
        log_info "✓ Daemon stopped"
        return 0
    else
        log_error "Failed to stop daemon"
        return 1
    fi
}

restart_daemon() {
    log_info "Restarting daemon..."
    stop_daemon || true
    sleep 1
    start_daemon
}

is_running() {
    if [ ! -f "${DAEMON_PID_FILE}" ]; then
        return 1
    fi
    
    local pid=$(cat "${DAEMON_PID_FILE}")
    kill -0 "${pid}" 2>/dev/null || return 1
}

status_daemon() {
    if is_running; then
        local pid=$(cat "${DAEMON_PID_FILE}")
        log_info "Daemon is running (PID: ${pid})"
        
        # Show last 5 log entries
        if [ -f "${REPO_ROOT}/logs/daemon-scheduler.log" ]; then
            log_info "Recent logs:"
            tail -5 "${REPO_ROOT}/logs/daemon-scheduler.log" | sed 's/^/  /'
        fi
        return 0
    else
        log_error "Daemon is not running"
        return 1
    fi
}

install_systemd() {
    if [ ! -f "${REPO_ROOT}/daemon-scheduler.service" ]; then
        log_error "Service file not found at ${REPO_ROOT}/daemon-scheduler.service"
        return 1
    fi
    
    log_info "Installing systemd service..."
    
    if ! command -v systemctl &> /dev/null; then
        log_error "systemd not available on this system"
        return 1
    fi
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "Must run as root to install systemd service"
        return 1
    fi
    
    cp "${REPO_ROOT}/daemon-scheduler.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable daemon-scheduler.service
    
    log_info "✓ Service installed"
    log_info "Start with: sudo systemctl start daemon-scheduler"
}

# Main
case "${1:-status}" in
    start)
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        restart_daemon
        ;;
    status)
        status_daemon
        ;;
    install-systemd)
        install_systemd
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|install-systemd}"
        exit 1
        ;;
esac
