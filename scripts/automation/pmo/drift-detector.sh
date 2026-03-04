#!/usr/bin/env bash
set -euo pipefail

# Drift Detection & Auto-Remediation Daemon
# Continuously validates that running infrastructure matches Git-driven configuration
# Provides automatic remediation for detected deviations
#
# Features:
#   - Git-based source of truth for runner configuration
#   - Continuous drift detection (every N minutes)
#   - Automatic remediation (restart services, reconfigure)
#   - Audit trail of all detected and fixed drifts
#   - Slack/email notifications for critical drifts

CONFIG_REPO="${CONFIG_REPO:-.}"
CONFIG_BRANCH="${CONFIG_BRANCH:-main}"
DRIFT_CHECK_INTERVAL="${DRIFT_CHECK_INTERVAL:-300}"  # 5 minutes
DRIFT_LOG="${DRIFT_LOG:-/var/log/runner-drifts.log}"
AUTO_REMEDIATE="${AUTO_REMEDIATE:-false}"
CRITICAL_DRIFT_WEBHOOK="${CRITICAL_DRIFT_WEBHOOK:-}"

mkdir -p "$(dirname "$DRIFT_LOG")"

log() {
  local severity="$1"
  shift
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [$severity] $*"
  echo "$msg"
  echo "$msg" >> "$DRIFT_LOG"
}

# Fetch latest config from Git
fetch_config() {
  log "INFO" "Fetching configuration from Git..."
  
  cd "$CONFIG_REPO" || return 1
  
  # Ensure clean working directory
  git status --porcelain > /dev/null || {
    log "WARN" "Local Git modifications detected, discarding..."
    git reset --hard HEAD
  }
  
  # Pull latest
  git fetch origin "$CONFIG_BRANCH" || true
  git checkout -q "origin/$CONFIG_BRANCH" || {
    log "ERROR" "Failed to checkout branch: $CONFIG_BRANCH"
    return 1
  }
  
  log "INFO" "Configuration synchronized (HEAD=$(git rev-parse --short HEAD))"
  return 0
}

# Check: Runner process status
check_runner_process() {
  local expected_status="$1"
  local actual_status=$(systemctl is-active actions-runner || echo "unknown")
  
  if [ "$actual_status" != "$expected_status" ]; then
    log "WARN" "DRIFT: Runner process status mismatch (expected=$expected_status, actual=$actual_status)"
    
    if [ "$AUTO_REMEDIATE" = "true" ]; then
      log "INFO" "AUTO-REMEDIATING: Restarting runner service..."
      systemctl restart actions-runner || log "ERROR" "Failed to restart runner"
    fi
    
    return 1
  fi
  
  return 0
}

# Check: System packages/capabilities
check_system_capabilities() {
  local manifest_file="${CONFIG_REPO}/.runner-config/capabilities.yaml"
  
  [ -f "$manifest_file" ] || return 0
  
  log "INFO" "Checking system capabilities..."
  
  local drift_count=0
  
  # Check required packages
  while IFS= read -r package; do
    if ! dpkg -l | grep -qE "^ii.*${package}"; then
      log "WARN" "DRIFT: Missing package: $package"
      ((drift_count++))
      
      if [ "$AUTO_REMEDIATE" = "true" ]; then
        log "INFO" "AUTO-REMEDIATING: Installing package $package..."
        apt-get install -y "$package" > /dev/null 2>&1 || \
          log "ERROR" "Failed to install package: $package"
      fi
    fi
  done < <(yq '.packages[]' "$manifest_file" 2>/dev/null)
  
  # Check required directories
  while IFS= read -r dir; do
    if [ ! -d "$dir" ]; then
      log "WARN" "DRIFT: Missing directory: $dir"
      ((drift_count++))
      
      if [ "$AUTO_REMEDIATE" = "true" ]; then
        log "INFO" "AUTO-REMEDIATING: Creating directory $dir..."
        mkdir -p "$dir" || log "ERROR" "Failed to create directory: $dir"
      fi
    fi
  done < <(yq '.directories[]' "$manifest_file" 2>/dev/null)
  
  return $drift_count
}

# Check: Environment variables
check_environment_config() {
  local manifest_file="${CONFIG_REPO}/.runner-config/environment.yaml"
  
  [ -f "$manifest_file" ] || return 0
  
  log "INFO" "Checking environment configuration..."
  
  local drift_count=0
  
  while IFS= read -r -d $'\0' key; do
    local expected_value=$(yq ".env.$key" "$manifest_file")
    local actual_value="${!key:-}"
    
    if [ "$actual_value" != "$expected_value" ]; then
      log "WARN" "DRIFT: Environment variable mismatch (var=$key, expected=$expected_value, actual=$actual_value)"
      ((drift_count++))
      
      if [ "$AUTO_REMEDIATE" = "true" ]; then
        log "INFO" "AUTO-REMEDIATING: Setting $key=$expected_value..."
        export "$key=$expected_value"
        # Persist via systemd environment file
        echo "$key=$expected_value" >> /etc/runner.env || true
      fi
    fi
  done < <(yq '.env | keys | .[]' "$manifest_file" 2>/dev/null | tr '\n' '\0')
  
  return $drift_count
}

# Check: Systemd configuration
check_systemd_config() {
  local manifest_file="${CONFIG_REPO}/.runner-config/systemd.yaml"
  
  [ -f "$manifest_file" ] || return 0
  
  log "INFO" "Checking systemd configuration..."
  
  local drift_count=0
  
  # Check service restart policy
  local expected_restart=$(yq '.services.actions-runner.restart' "$manifest_file")
  local actual_restart=$(systemctl show -p Restart --value actions-runner)
  
  if [ "$actual_restart" != "$expected_restart" ]; then
    log "WARN" "DRIFT: Systemd Restart policy mismatch (expected=$expected_restart, actual=$actual_restart)"
    ((drift_count++))
  fi
  
  # Check enabled status
  local expected_enabled=$(yq '.services.actions-runner.enabled' "$manifest_file")
  if [ "$expected_enabled" = "true" ]; then
    if ! systemctl is-enabled actions-runner > /dev/null 2>&1; then
      log "WARN" "DRIFT: Service not enabled at boot (actions-runner)"
      ((drift_count++))
      
      if [ "$AUTO_REMEDIATE" = "true" ]; then
        log "INFO" "AUTO-REMEDIATING: Enabling service..."
        systemctl enable actions-runner || log "ERROR" "Failed to enable service"
      fi
    fi
  fi
  
  return $drift_count
}

# Check: File permissions and ownership
check_file_permissions() {
  local manifest_file="${CONFIG_REPO}/.runner-config/file-permissions.yaml"
  
  [ -f "$manifest_file" ] || return 0
  
  log "INFO" "Checking file permissions..."
  
  local drift_count=0
  
  while IFS= read -r -d $'\0' file_path; do
    [ ! -e "$file_path" ] && continue
    
    local expected_perms=$(yq ".files.\"$file_path\".permissions" "$manifest_file")
    local actual_perms=$(stat -c %a "$file_path")
    
    if [ "$actual_perms" != "$expected_perms" ]; then
      log "WARN" "DRIFT: File permissions mismatch (file=$file_path, expected=$expected_perms, actual=$actual_perms)"
      ((drift_count++))
      
      if [ "$AUTO_REMEDIATE" = "true" ]; then
        log "INFO" "AUTO-REMEDIATING: Fixing permissions $file_path..."
        chmod "$expected_perms" "$file_path" || log "ERROR" "Failed to fix permissions"
      fi
    fi
  done < <(yq '.files | keys | .[]' "$manifest_file" 2>/dev/null | tr '\n' '\0')
  
  return $drift_count
}

# Check: Running processes and expected daemons
check_running_processes() {
  local manifest_file="${CONFIG_REPO}/.runner-config/processes.yaml"
  
  [ -f "$manifest_file" ] || return 0
  
  log "INFO" "Checking running processes..."
  
  local drift_count=0
  
  while IFS= read -r process; do
    if ! pgrep -f "$process" > /dev/null 2>&1; then
      log "WARN" "DRIFT: Expected process not running: $process"
      ((drift_count++))
      
      if [ "$AUTO_REMEDIATE" = "true" ]; then
        log "INFO" "AUTO-REMEDIATING: Restarting process group..."
        systemctl restart "${process%% *}" || true
      fi
    fi
  done < <(yq '.required_processes[]' "$manifest_file" 2>/dev/null)
  
  return $drift_count
}

# Generate drift report
generate_drift_report() {
  log "INFO" "Generating drift report..."
  
  local report_file="/tmp/drift-report-$(date +%s).txt"
  
  cat > "$report_file" <<EOF
Drift Detection Report
Generated: $(date -Iseconds)
Repository: $CONFIG_REPO
Branch: $CONFIG_BRANCH
Hostname: $(hostname)
Kernel: $(uname -r)

System Status:
  Runner Process: $(systemctl is-active actions-runner || echo "unknown")
  Health Monitor: $(systemctl is-active elevatediq-runner-health-monitor.timer || echo "unknown")
  
Recent Drifts (last 10):
EOF
  
  tail -10 "$DRIFT_LOG" >> "$report_file"
  
  log "INFO" "Report saved: $report_file"
  
  # Send report if webhook configured
  if [ -n "$CRITICAL_DRIFT_WEBHOOK" ]; then
    log "INFO" "Sending drift report to webhook..."
    curl -X POST "$CRITICAL_DRIFT_WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "{\"hostname\": \"$(hostname)\", \"drifts\": $(wc -l < "$DRIFT_LOG\")}" \
      2>/dev/null || log "WARN" "Failed to send webhook"
  fi
}

# Main drift check
run_drift_check() {
  log "INFO" "Starting drift detection cycle..."
  
  # Sync config from Git
  fetch_config || log "ERROR" "Failed to fetch config"
  
  # Run all checks
  local total_drifts=0
  
  check_runner_process "active" || ((total_drifts++))
  check_system_capabilities || ((total_drifts += $?))
  check_environment_config || ((total_drifts += $?))
  check_systemd_config || ((total_drifts += $?))
  check_file_permissions || ((total_drifts += $?))
  check_running_processes || ((total_drifts += $?))
  
  if [ $total_drifts -gt 0 ]; then
    log "WARN" "Drift check complete: $total_drifts drift(s) detected"
    
    if [ "$total_drifts" -gt 5 ]; then
      log "CRIT" "Critical: Multiple drifts detected, generating report..."
      generate_drift_report
    fi
    
    return 1
  else
    log "INFO" "✓ Infrastructure consistent with configuration"
    return 0
  fi
}

# Continuous monitoring loop
run_daemon() {
  log "INFO" "🔍 Starting Drift Detection Daemon (interval: ${DRIFT_CHECK_INTERVAL}s, auto-remediate=$AUTO_REMEDIATE)"
  
  while true; do
    run_drift_check
    sleep "$DRIFT_CHECK_INTERVAL"
  done
}

# CLI
main() {
  case "${1:-help}" in
    check)
      run_drift_check
      ;;
    run)
      run_daemon
      ;;
    report)
      generate_drift_report
      ;;
    *)
      cat <<'HELP'
Drift Detection & Auto-Remediation Daemon

Usage:
  drift-detector check                               Run single drift check
  drift-detector run                                 Start continuous monitoring
  drift-detector report                              Generate drift report

Configuration (in Git):
  .runner-config/
    ├── capabilities.yaml       Required packages, directories, tools
    ├── environment.yaml         Environment variables
    ├── systemd.yaml            Systemd service configuration
    ├── file-permissions.yaml   File ownership and permissions
    └── processes.yaml          Expected running processes

Environment Variables:
  CONFIG_REPO                   Git repository with configuration
  CONFIG_BRANCH                 Git branch (default: main)
  DRIFT_CHECK_INTERVAL          Check interval in seconds (default: 300)
  AUTO_REMEDIATE                Enable automatic fixing (default: false)
  CRITICAL_DRIFT_WEBHOOK        Webhook URL for critical drifts

Example Configuration (capabilities.yaml):
  packages:
    - docker.io
    - git
    - jq
  
  directories:
    - /home/runner
    - /var/log/runner

Auto-Remediation:
  - Set AUTO_REMEDIATE=true to enable automatic fixing
  - All remediations are logged for audit trail
  - Critical drifts (>5) trigger webhook notification

HELP
      exit 1
      ;;
  esac
}

main "$@"
