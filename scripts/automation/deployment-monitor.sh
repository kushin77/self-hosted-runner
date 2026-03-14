#!/bin/bash
#
# Deployment Monitoring & Polling System
#
# Purpose: Monitor production deployment in real-time
#         - Poll Cloud Build status
#         - Track component health
#         - Update GitHub issue with status
#         - Alert on errors/failures
#
# Usage:
#   ./monitor-deployment.sh --build-id BUILD_ID --issue 3103
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
readonly MONITORING_LOG="${REPO_ROOT}/.deployment-monitoring.log"
readonly POLL_INTERVAL=10  # seconds
readonly MAX_WAIT_TIME=3600  # 1 hour

BUILD_ID="${1:-}"
ISSUE_NUMBER="${2:-3103}"
OWNER="kushin77"
REPO="self-hosted-runner"

# State tracking
declare -A COMPONENT_STATUS
declare -A COMPONENT_TIMES

# Logging
log_monitor() {
  local TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
  echo "[${TIMESTAMP}] $*" | tee -a "${MONITORING_LOG}"
}

error_alert() {
  local TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
  echo "[${TIMESTAMP}] ❌ ERROR: $*" | tee -a "${MONITORING_LOG}"
  return 1
}

# Get Cloud Build status
get_build_status() {
  local BID="$1"
  
  gcloud builds describe "${BID}" \
    --format='value(status)' 2>/dev/null || echo "UNKNOWN"
}

# Get build logs
get_build_logs() {
  local BID="$1"
  
  gcloud builds log "${BID}" --limit=50 2>/dev/null || echo "No logs available"
}

# Update GitHub issue with status
update_issue_status() {
  local ISSUE_NUM="$1"
  local BUILD_STATUS="$2"
  local BUILD_ID_VAL="$3"
  
  local STATUS_EMOJI="🟡"
  local STATUS_TEXT="ONGOING"
  
  case "${BUILD_STATUS}" in
    SUCCESS)
      STATUS_EMOJI="🟢"
      STATUS_TEXT="SUCCESS"
      ;;
    FAILURE)
      STATUS_EMOJI="🔴"
      STATUS_TEXT="FAILED"
      ;;
    TIMEOUT)
      STATUS_EMOJI="🟠"
      STATUS_TEXT="TIMEOUT"
      ;;
    QUEUED)
      STATUS_EMOJI="🟡"
      STATUS_TEXT="QUEUED"
      ;;
    WORKING)
      STATUS_EMOJI="🟡"
      STATUS_TEXT="WORKING"
      ;;
  esac
  
  local CURRENT_TIME=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  
  # Build issue body with current status
  local ISSUE_BODY="## Deployment Monitoring Dashboard

**Status**: ${STATUS_EMOJI} ${STATUS_TEXT}  
**Build ID**: ${BUILD_ID_VAL}  
**Last Update**: ${CURRENT_TIME}  
**Deployment**: Production (All Components)  

### Current Status

Build Status: \`${BUILD_STATUS}\`

### Recent Logs

\`\`\`
$(get_build_logs "${BUILD_ID_VAL}" | tail -20)
\`\`\`

### Monitoring Progress

- [x] Git status verified (clean)
- [x] Prerequisites checked (gcloud, kubectl, jq)
- [x] Cloud Build triggered
- $([ "${BUILD_STATUS}" != "QUEUED" ] && echo "✓" || echo "⏳") Build job started
- $([ "${BUILD_STATUS}" == "WORKING" ] || [ "${BUILD_STATUS}" == "SUCCESS" ] && echo "✓" || echo "⏳") Processing...
- $([ "${BUILD_STATUS}" == "SUCCESS" ] && echo "✓" || echo "⏳") Deployment verification

### Build Timeline

\`\`\`
Started:  $(date -u +'%Y-%m-%dT%H:%M:%SZ')
Last Update: ${CURRENT_TIME}
Duration: Computing...
\`\`\`

---

**Real-time Updates**: This issue is automatically updated every 10 seconds  
**Next Update**: $(date -u -d '+10 seconds' +'%Y-%m-%dT%H:%M:%SZ') UTC"
  
  # Update issue with comment instead of body modification
  mcp_github_github_add_issue_comment \
    owner="${OWNER}" \
    repo="${REPO}" \
    issue_number="${ISSUE_NUM}" \
    body="**[$(date +'%H:%M:%S UTC')]** Build Status: ${STATUS_EMOJI} ${STATUS_TEXT}

Build: \`${BUILD_ID_VAL}\`
Status: \`${BUILD_STATUS}\`" 2>/dev/null || true
}

# Monitor component deployment
monitor_component() {
  local COMPONENT="$1"
  local EXPECTED_REPLICAS="${2:-1}"
  
  log_monitor "Checking component: ${COMPONENT}"
  
  # Try to get K8s deployment status
  local READY=$(kubectl get deployment "${COMPONENT}" -n prod \
    --format='count(status.conditions[?(@.type=="Available")].status=="True")' 2>/dev/null || echo "0")
  
  if [[ "${READY}" -gt 0 ]]; then
    log_monitor "  ✓ Component ${COMPONENT} is ready"
    COMPONENT_STATUS["${COMPONENT}"]="READY"
    return 0
  else
    log_monitor "  ⏳ Component ${COMPONENT} is deploying..."
    COMPONENT_STATUS["${COMPONENT}"]="DEPLOYING"
    return 1
  fi
}

# Perform health check
health_check() {
  log_monitor "Running health checks..."
  
  # Try to run cluster readiness check
  if bash "${REPO_ROOT}/scripts/k8s-health-checks/cluster-readiness.sh" \
    --environment prod &>/dev/null; then
    log_monitor "  ✓ Cluster health check passed"
    return 0
  else
    log_monitor "  ⚠️  Cluster health check in progress or failed"
    return 1
  fi
}

# Main monitoring loop
main() {
  if [[ -z "${BUILD_ID}" ]]; then
    error_alert "BUILD_ID required as first argument"
    return 1
  fi
  
  log_monitor "🚀 Starting deployment monitoring"
  log_monitor "Build ID: ${BUILD_ID}"
  log_monitor "Issue Number: ${ISSUE_NUMBER}"
  
  local ELAPSED=0
  local PREVIOUS_STATUS="UNKNOWN"
  
  while [[ $ELAPSED -lt $MAX_WAIT_TIME ]]; do
    local BUILD_STATUS=$(get_build_status "${BUILD_ID}")
    
    # Log status change
    if [[ "${BUILD_STATUS}" != "${PREVIOUS_STATUS}" ]]; then
      log_monitor "Build status changed: ${PREVIOUS_STATUS} → ${BUILD_STATUS}"
      update_issue_status "${ISSUE_NUMBER}" "${BUILD_STATUS}" "${BUILD_ID}"
      PREVIOUS_STATUS="${BUILD_STATUS}"
    fi
    
    # Handle completion
    case "${BUILD_STATUS}" in
      SUCCESS)
        log_monitor "✓ Build completed successfully!"
        log_monitor "Running post-deployment health checks..."
        
        if health_check; then
          log_monitor "✓ Health checks passed"
          update_issue_status "${ISSUE_NUMBER}" "SUCCESS" "${BUILD_ID}"
          log_monitor "🎉 Deployment completed successfully!"
          return 0
        else
          log_monitor "⚠️  Health checks incomplete or pending"
        fi
        ;;
        
      FAILURE)
        log_monitor "❌ Build failed!"
        update_issue_status "${ISSUE_NUMBER}" "FAILURE" "${BUILD_ID}"
        error_alert "Deployment failed. Check logs at:"
        error_alert "  gcloud builds log ${BUILD_ID} --stream"
        return 1
        ;;
        
      TIMEOUT)
        log_monitor "⏱️  Build timed out"
        update_issue_status "${ISSUE_NUMBER}" "TIMEOUT" "${BUILD_ID}"
        error_alert "Deployment timeout after ${MAX_WAIT_TIME} seconds"
        return 1
        ;;
        
      QUEUED|WORKING)
        # Still processing
        log_monitor "Status: ${BUILD_STATUS} - Elapsed: ${ELAPSED}s"
        ;;
    esac
    
    # Wait before next poll
    sleep ${POLL_INTERVAL}
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
  done
  
  error_alert "Monitoring timeout after ${MAX_WAIT_TIME} seconds"
  return 1
}

# Run main
main "$@"
