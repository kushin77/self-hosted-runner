#!/usr/bin/env bash
# =============================================================================
# scripts/scm/setup-github-runners.sh
# Purpose: Pre-register GitHub self-hosted runners with label 'scm-failover'
#          so they are ready BEFORE any GitLab failover event.
# Usage:   ./scripts/scm/setup-github-runners.sh [--dry-run] [--count N]
# NIST:    CP-7 (Alternate Processing Site), CP-9 (System Backup)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="/var/log/scm-setup/runner-registration.log"
DRY_RUN=false
RUNNER_COUNT=2
RUNNER_LABELS="scm-failover,self-hosted,linux,x64"
RUNNER_GROUP="Default"
RUNNER_WORK_DIR="/tmp/github-runner-work"
GITHUB_REPO="${SCM_GITHUB_REPO:-kushin77/ElevatedIQ-Mono-Repo}"
RUNNER_VERSION="2.314.1"
RUNNER_ARCH="linux-x64"
RUNNER_DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "${LOG_FILE}" 2>/dev/null || echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
die() { log "FATAL: $*"; exit 1; }
dry_echo() { if [[ "${DRY_RUN}" == "true" ]]; then log "[DRY-RUN] $*"; else eval "$*"; fi; }

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --dry-run       Print commands without executing"
  echo "  --count N       Number of runners to register (default: 2)"
  echo "  --deregister    Deregister all 'scm-failover' labelled runners"
  echo "  --status        List registered scm-failover runners"
  echo "  --help          Show this help"
  echo ""
  echo "Required env vars:"
  echo "  GITHUB_FAILOVER_PAT   GitHub PAT with 'repo' and 'admin:org' scopes"
  echo "  SCM_GITHUB_REPO       Optional: owner/repo (default: kushin77/ElevatedIQ-Mono-Repo)"
}

check_prereqs() {
  for cmd in curl tar jq; do
    command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} not found — install it first"
  done
  [[ -n "${GITHUB_FAILOVER_PAT:-}" ]] || die "GITHUB_FAILOVER_PAT env var not set"
}

get_registration_token() {
  log "Fetching runner registration token from GitHub API..."
  curl -s -X POST \
    -H "Authorization: token ${GITHUB_FAILOVER_PAT}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" \
    | jq -r '.token' || die "Failed to fetch registration token"
}

download_runner() {
  local install_dir="$1"
  if [[ -d "${install_dir}" ]]; then
    log "Runner directory already exists: ${install_dir} — skipping download"
    return
  fi
  log "Downloading GitHub runner v${RUNNER_VERSION}..."
  mkdir -p "${install_dir}"
  curl -sSL "${RUNNER_DOWNLOAD_URL}" -o /tmp/actions-runner.tar.gz
  tar xzf /tmp/actions-runner.tar.gz -C "${install_dir}"
  rm -f /tmp/actions-runner.tar.gz
  log "Runner downloaded to ${install_dir}"
}

register_runner() {
  local id="$1"
  local install_dir="${RUNNER_WORK_DIR}/runner-${id}"
  local runner_name="scm-failover-$(hostname)-${id}"

  download_runner "${install_dir}"

  local reg_token
  reg_token=$(get_registration_token)

  log "Registering runner ${runner_name} with labels: ${RUNNER_LABELS}..."
  dry_echo "${install_dir}/config.sh \
    --url 'https://github.com/${GITHUB_REPO}' \
    --token '${reg_token}' \
    --name '${runner_name}' \
    --labels '${RUNNER_LABELS}' \
    --runnergroup '${RUNNER_GROUP}' \
    --work '_work' \
    --unattended \
    --replace"

  if [[ "${DRY_RUN}" != "true" ]]; then
    # Install as systemd service
    dry_echo "sudo ${install_dir}/svc.sh install ${runner_name} || true"
    dry_echo "sudo ${install_dir}/svc.sh start"
    log "Runner ${runner_name} registered and started"
  fi
}

deregister_runners() {
  log "Listing scm-failover runners to deregister..."
  local runners
  runners=$(curl -s \
    -H "Authorization: token ${GITHUB_FAILOVER_PAT}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/runners?per_page=100" \
    | jq -r '.runners[] | select(.labels[].name == "scm-failover") | "\(.id) \(.name)"')

  if [[ -z "${runners}" ]]; then
    log "No scm-failover runners found"
    return
  fi

  echo "${runners}" | while read -r runner_id runner_name; do
    log "Deregistering runner ${runner_name} (ID: ${runner_id})..."
    dry_echo "curl -s -X DELETE \
      -H 'Authorization: token ${GITHUB_FAILOVER_PAT}' \
      -H 'Accept: application/vnd.github.v3+json' \
      'https://api.github.com/repos/${GITHUB_REPO}/actions/runners/${runner_id}'"
  done
}

status_runners() {
  log "=== scm-failover runners for ${GITHUB_REPO} ==="
  curl -s \
    -H "Authorization: token ${GITHUB_FAILOVER_PAT}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/runners?per_page=100" \
    | jq -r '.runners[] | select(.labels[].name == "scm-failover") | "  \(.status) | \(.name) | OS: \(.os) | Labels: \([.labels[].name] | join(","))"'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
ACTION="register"
mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)     DRY_RUN=true; shift ;;
    --count)       RUNNER_COUNT="$2"; shift 2 ;;
    --deregister)  ACTION="deregister"; shift ;;
    --status)      ACTION="status"; shift ;;
    --help)        usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

log "=== GitHub Runner Setup Script (NIST CP-7) ==="
log "Action: ${ACTION} | Repo: ${GITHUB_REPO} | DryRun: ${DRY_RUN}"

check_prereqs

case "${ACTION}" in
  register)
    for i in $(seq 1 "${RUNNER_COUNT}"); do
      register_runner "${i}"
    done
    log "✅ ${RUNNER_COUNT} scm-failover runner(s) registered"
    ;;
  deregister)  deregister_runners ;;
  status)      status_runners ;;
esac
