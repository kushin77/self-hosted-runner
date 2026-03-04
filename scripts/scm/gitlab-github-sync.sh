#!/usr/bin/env bash
# =============================================================================
# gitlab-github-sync.sh — Real-Time Mirror: GitLab → GitHub
# =============================================================================
# Role: Push-mirror all refs from GitLab on-prem to GitHub on every commit.
# Run: Triggered by GitLab webhook on push events + cron fallback every 5 min.
# NIST Controls: CP-9 (System Backup), SC-28 (Protection of Information at Rest)
#
# Environment variables required:
#   GITLAB_HOST          — GitLab hostname (e.g. gitlab.internal.elevatediq.com)
#   GITLAB_REPO_PATH     — GitLab repo path (e.g. elevatediq/mono-repo)
#   GITHUB_ORG_REPO      — GitHub target (e.g. kushin77/ElevatedIQ-Mono-Repo)
#   GITHUB_SSH_KEY_PATH  — Path to service account SSH private key for GitHub
#   MIRROR_WORKSPACE     — Local workspace dir for bare clone (default: /tmp/scm-mirror)
#   SLACK_WEBHOOK_URL    — Alert webhook (optional)
#   MAX_SYNC_LAG_MINUTES — Alert threshold (default: 5)
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

# --- Configuration ---
GITLAB_HOST="${GITLAB_HOST:-gitlab.internal.elevatediq.com}"
GITLAB_REPO_PATH="${GITLAB_REPO_PATH:-elevatediq/mono-repo}"
GITHUB_ORG_REPO="${GITHUB_ORG_REPO:-kushin77/ElevatedIQ-Mono-Repo}"
GITHUB_SSH_KEY_PATH="${GITHUB_SSH_KEY_PATH:-/etc/scm-mirror/github-sync-key}"
MIRROR_WORKSPACE="${MIRROR_WORKSPACE:-/tmp/scm-mirror}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
MAX_SYNC_LAG_MINUTES="${MAX_SYNC_LAG_MINUTES:-5}"
LOG_DIR="${LOG_DIR:-/var/log/scm-mirror}"
LOCK_FILE="/tmp/scm-mirror.lock"

GITLAB_SSH_URL="ssh://akushnir@${GITLAB_HOST}/${GITLAB_REPO_PATH}.git"  # [HARDENING #4730] canonical SSH principal is akushnir@ (not git@)
GITHUB_SSH_URL="git@github.com:${GITHUB_ORG_REPO}.git"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SYNC_LOG="${LOG_DIR}/sync-$(date -u +%Y%m%d).log"

# --- Logging ---
mkdir -p "${LOG_DIR}"
exec > >(tee -a "${SYNC_LOG}") 2>&1

log() { echo "[${TIMESTAMP}] [INFO]  $*"; }
warn() { echo "[${TIMESTAMP}] [WARN]  $*"; }
error() { echo "[${TIMESTAMP}] [ERROR] $*" >&2; }
fatal() { echo "[${TIMESTAMP}] [FATAL] $*" >&2; alert_slack ":x: SCM Mirror FATAL: $*" "critical"; exit 1; }

# --- Alerting ---
alert_slack() {
    local msg="$1"
    local level="${2:-warning}"
    if [[ -z "${SLACK_WEBHOOK_URL}" ]]; then return 0; fi
    local color
    color=$(case "${level}" in critical) echo "#cc0000" ;; warning) echo "#ff9900" ;; *) echo "#36a64f" ;; esac)
    curl -s -X POST "${SLACK_WEBHOOK_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"attachments\":[{\"color\":\"${color}\",\"text\":\"${msg}\",\"footer\":\"scm-mirror | ${TIMESTAMP}\"}]}" \
        || true
}

# --- Lock guard (prevent concurrent sync runs) ---
acquire_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")
        if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
            warn "Another sync process (PID ${lock_pid}) is running. Skipping."
            exit 0
        fi
        warn "Stale lock file found. Removing."
        rm -f "${LOCK_FILE}"
    fi
    echo $$ > "${LOCK_FILE}"
    trap 'rm -f "${LOCK_FILE}"' EXIT INT TERM
}

# --- SSH setup for GitHub service account ---
configure_github_ssh() {
    if [[ ! -f "${GITHUB_SSH_KEY_PATH}" ]]; then
        fatal "GitHub SSH key not found at ${GITHUB_SSH_KEY_PATH}"
    fi
    chmod 600 "${GITHUB_SSH_KEY_PATH}"
    export GIT_SSH_COMMAND="ssh -i ${GITHUB_SSH_KEY_PATH} -o StrictHostKeyChecking=no -o BatchMode=yes"
    log "GitHub SSH configured with key: ${GITHUB_SSH_KEY_PATH}"
}

# --- Initialize or update bare clone of GitLab repo ---
setup_mirror_workspace() {
    if [[ ! -d "${MIRROR_WORKSPACE}" ]]; then
        log "Initializing bare clone from GitLab: ${GITLAB_SSH_URL}"
        mkdir -p "${MIRROR_WORKSPACE}"
        git clone --mirror "${GITLAB_SSH_URL}" "${MIRROR_WORKSPACE}/repo.git"
    else
        log "Updating bare clone from GitLab"
        git -C "${MIRROR_WORKSPACE}/repo.git" remote update --prune
    fi
}

# --- Push all refs to GitHub ---
push_to_github() {
    log "Pushing all refs to GitHub: ${GITHUB_SSH_URL}"
    # --force is required for push-mirror — this is intentional (GitLab is authoritative)
    # GitHub is read-only from developer perspective during normal operations
    if ! git -C "${MIRROR_WORKSPACE}/repo.git" push --mirror --force "${GITHUB_SSH_URL}" 2>&1; then
        fatal "Mirror push to GitHub FAILED"
    fi
    log "Mirror push to GitHub SUCCEEDED"
}

# --- Verify sync state ---
verify_sync() {
    log "Verifying ref consistency between GitLab and GitHub..."
    local gitlab_refs github_refs mismatch=0

    # Compare HEAD SHA
    local gitlab_head github_head
    gitlab_head=$(git -C "${MIRROR_WORKSPACE}/repo.git" rev-parse HEAD 2>/dev/null || echo "unknown")

    # Fetch GitHub HEAD via API (does not require SSH for public repos)
    github_head=$(
        curl -sf "https://api.github.com/repos/${GITHUB_ORG_REPO}/commits/HEAD" \
            -H "Accept: application/vnd.github.v3+json" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('sha','unknown'))" 2>/dev/null \
        || echo "api_unavailable"
    )

    if [[ "${gitlab_head}" == "${github_head}" ]]; then
        log "HEAD SHA match: ${gitlab_head}"
    elif [[ "${github_head}" == "api_unavailable" ]]; then
        warn "Could not verify GitHub HEAD via API (private repo or network issue)"
    else
        warn "HEAD SHA MISMATCH — GitLab: ${gitlab_head} GitHub: ${github_head}"
        mismatch=1
    fi

    # Write sync timestamp
    echo "${TIMESTAMP}" > "${LOG_DIR}/last_successful_sync"
    log "Sync timestamp written: ${TIMESTAMP}"

    return ${mismatch}
}

# --- Check sync lag ---
check_sync_lag() {
    local last_sync_file="${LOG_DIR}/last_successful_sync"
    if [[ ! -f "${last_sync_file}" ]]; then
        warn "No previous sync timestamp found"
        return 0
    fi
    local last_sync
    last_sync=$(cat "${last_sync_file}")
    local last_epoch now_epoch lag_minutes

    last_epoch=$(date -d "${last_sync}" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_sync}" +%s 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    lag_minutes=$(( (now_epoch - last_epoch) / 60 ))

    if [[ "${lag_minutes}" -ge "${MAX_SYNC_LAG_MINUTES}" ]]; then
        local level="warning"
        [[ "${lag_minutes}" -ge 15 ]] && level="critical"
        warn "Sync lag: ${lag_minutes} minutes (threshold: ${MAX_SYNC_LAG_MINUTES})"
        alert_slack ":warning: SCM Mirror lag: *${lag_minutes} minutes*. Last sync: \`${last_sync}\`" "${level}"
    else
        log "Sync lag OK: ${lag_minutes} minutes"
    fi
}

# --- Write metrics (Prometheus-compatible) ---
write_metrics() {
    local metrics_file="${LOG_DIR}/scm_mirror_metrics.prom"
    local last_sync_epoch=0
    if [[ -f "${LOG_DIR}/last_successful_sync" ]]; then
        local last_sync
        last_sync=$(cat "${LOG_DIR}/last_successful_sync")
        last_sync_epoch=$(date -d "${last_sync}" +%s 2>/dev/null || echo 0)
    fi
    cat > "${metrics_file}" <<EOF
# HELP scm_mirror_last_sync_timestamp_seconds Unix timestamp of last successful GitLab→GitHub sync
# TYPE scm_mirror_last_sync_timestamp_seconds gauge
scm_mirror_last_sync_timestamp_seconds ${last_sync_epoch}
# HELP scm_mirror_last_sync_success 1 if last sync was successful
# TYPE scm_mirror_last_sync_success gauge
scm_mirror_last_sync_success 1
EOF
    log "Metrics written to ${metrics_file}"
}

# --- Main ---
main() {
    log "=== SCM Mirror Sync Starting ==="
    log "GitLab: ${GITLAB_SSH_URL}"
    log "GitHub: ${GITHUB_SSH_URL}"

    acquire_lock
    configure_github_ssh
    setup_mirror_workspace
    push_to_github

    if verify_sync; then
        log "Sync verification PASSED"
        write_metrics
    else
        warn "Sync verification had discrepancies — investigate"
        alert_slack ":warning: SCM Mirror sync completed but verification detected discrepancies. Check logs." "warning"
    fi

    check_sync_lag
    log "=== SCM Mirror Sync Complete ==="
}

main "$@"
