#!/usr/bin/env bash
# =============================================================================
# scripts/scm/setup-gitlab-runners.sh
# Purpose: Pre-register GitLab runners with label 'scm-failover'
#          so they are ready BEFORE any GitHub failover event.
# NIST:    CP-7 (Alternate Processing Site), CP-9 (System Backup) [GAP-010]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE="/var/log/scm-setup/gitlab-runner-registration.log"
DRY_RUN=false
RUNNER_COUNT=2
RUNNER_TAGS="scm-failover,high-mem,fedramp-ready"
GITLAB_URL="${GITLAB_URL:-https://gitlab.internal.elevatediq.com}"
RUNNER_VERSION="v16.9.0"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "${LOG_FILE}" 2>/dev/null || echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }
die() { log "FATAL: $*"; exit 1; }

check_prereqs() {
  for cmd in curl gitlab-runner; do
    command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} not found — install it first"
  done
  [[ -n "${GITLAB_RUNNER_TOKEN:-}" ]] || die "GITLAB_RUNNER_TOKEN env var not set"
}

register_runner() {
  local id="$1"
  local runner_name="scm-failover-$(hostname)-${id}"

  log "Registering GitLab runner ${runner_name} with tags: ${RUNNER_TAGS}..."

  if [[ "${DRY_RUN}" == "true" ]]; then
    log "[DRY-RUN] gitlab-runner register --non-interactive --url '${GITLAB_URL}' --registration-token 'HIDDEN' --name '${runner_name}' --tag-list '${RUNNER_TAGS}' --executor 'shell'"
    return
  fi

  gitlab-runner register \
    --non-interactive \
    --url "${GITLAB_URL}" \
    --token "${GITLAB_RUNNER_TOKEN}" \
    --name "${runner_name}" \
    --tag-list "${RUNNER_TAGS}" \
    --executor "shell" \
    --shell "bash" \
    --docker-image "python:3.12-slim"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "Starting GitLab runner provisioning for SCM Resilience [NIST-CP-7]..."
check_prereqs

for ((i=1; i<=RUNNER_COUNT; i++)); do
  register_runner "${i}"
done

log "Provisioning complete. Verify status in: ${GITLAB_URL}/admin/runners"
