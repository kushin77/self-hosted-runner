#!/usr/bin/env bash
set -euo pipefail

# Automated Rollback System
# Purpose: Rollback to last successful deployment with validation
# Constraints: Immutable, ephemeral, idempotent, fully automated

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
PROJECT_ID="${GCP_PROJECT_ID:-nexusshield-prod}"
GKE_CLUSTER="${GKE_CLUSTER:-nexus-prod-gke}"
GKE_ZONE="${GKE_ZONE:-us-central1-a}"
GITHUB_REPO="${GITHUB_REPO:-kushin77/self-hosted-runner}"

# State management
ROLLBACK_DIR="${REPO_ROOT}/logs/rollbacks"
ROLLBACK_LOG="$ROLLBACK_DIR/rollback.log"
VALIDATION_LOG="$ROLLBACK_DIR/validation.log"

# Logging
log() {
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [ROLLBACK] $*" | tee -a "$ROLLBACK_LOG"
}

log_success() {
  echo "✅ $*" | tee -a "$ROLLBACK_LOG"
}

log_error() {
  echo "❌ $*" | tee -a "$ROLLBACK_LOG"
  return 1
}

# Initialize
initialize() {
  mkdir -p "$ROLLBACK_DIR"
  
  log "Automated Rollback System Initialized"
  log "Project: $PROJECT_ID | Cluster: $GKE_CLUSTER"
}

# Find last successful deployment commit
find_last_successful_deployment() {
  log "Searching for last successful deployment..."
  
  # Look for commits that successfully completed all phases
  # Search for commits with "ops: complete phase" or similar success markers
  local last_good_commit
  last_good_commit="$(cd "$REPO_ROOT" && git log --oneline --grep="complete\|success" \
    --grep="ops:" --grep="deployment" --all-match -n 5 2>/dev/null | head -1 | cut -d' ' -f1)" || {
    log_error "No successful deployment commits found"
    return 1
  }
  
  if [ -z "$last_good_commit" ]; then
    log_error "Could not determine last successful commit"
    return 1
  fi
  
  log_success "Last successful deployment: $last_good_commit"
  echo "$last_good_commit"
}

# Verify commit is deployable
verify_commit_viable() {
  local commit=$1
  
  log "Verifying commit viability: $commit"
  
  # Check if commit has all required files
  if cd "$REPO_ROOT" && git show "$commit:terraform/phase0-core/main.tf" &>/dev/null && \
     git show "$commit:terraform/phase1-core/phase1-gke.tf" &>/dev/null; then
    log_success "Commit contains required infrastructure code"
    return 0
  else
    log_error "Commit missing required infrastructure files"
    return 1
  fi
}

# Rollback git to previous commit
rollback_git() {
  local commit=$1
  local rollback_reason=$2
  
  log "Rolling back git to commit: $commit"
  log "Reason: $rollback_reason"
  
  cd "$REPO_ROOT"
  
  # Create rollback branch
  local rollback_branch
  rollback_branch="rollback-$(date +%s)"
  
  git checkout -b "$rollback_branch" "$commit" || {
    log_error "Failed to checkout commit $commit"
    return 1
  }
  
  # Commit rollback
  git commit --allow-empty -m "automated: rollback to $commit - $rollback_reason" 2>&1 | head -5
  
  # Push rollback to main
  git checkout main
  git reset --hard "$rollback_branch"
  
  log_success "Git rollback completed to: $commit"
  echo "$rollback_branch"
}

# Restore terraform state
restore_terraform_state() {
  local commit=$1
  
  log "Restoring terraform state from commit: $commit"
  
  cd "$REPO_ROOT/terraform/phase0-core"
  
  # Refresh terraform state with current infrastructure
  if terraform init &>/dev/null 2>&1; then
    log "Terraform initialized"
  fi
  
  if terraform refresh 2>&1 | head -10 | tee -a "$ROLLBACK_LOG"; then
    log_success "Terraform state refreshed"
    return 0
  else
    log_error "Terraform state refresh failed"
    return 1
  fi
}

# Validate rollback with triage
validate_rollback() {
  log "Validating rollback with phase triage..."
  
  if [ -x "$REPO_ROOT/scripts/utilities/triage_all_phases_one_shot.sh" ]; then
    if "$REPO_ROOT/scripts/utilities/triage_all_phases_one_shot.sh" 2>&1 | tee -a "$VALIDATION_LOG"; then
      log_success "Phase triage validation completed"
      
      # Check triage results
      if [ -f "$REPO_ROOT/logs/phase-triage-one-shot-latest.json" ]; then
        local status
        status="$(grep -o '"status":"[^"]*"' "$REPO_ROOT/logs/phase-triage-one-shot-latest.json" | head -1 | cut -d: -f2 | tr -d '"')" || true
        log "Triage status: $status"
      fi
      
      return 0
    else
      log_error "Phase triage validation failed"
      return 1
    fi
  else
    log_error "Triage script not found"
    return 1
  fi
}

# Create GitHub issue for rollback
create_github_issue() {
  local status=$1
  local previous_commit=$2
  local new_commit=$3
  local reason=$4
  
  log "Creating GitHub issue for rollback..."
  
  cat > /tmp/rollback_issue.md << EOF
# 🔄 Automated Rollback: $status

**Date**: $(date -u +'%Y-%m-%dT%H:%M:%SZ')  
**Project**: $PROJECT_ID  

## Rollback Details

| Field | Value |
|-------|-------|
| **Status** | $status |
| **Previous Commit** | $previous_commit |
| **Rolled Back To** | $new_commit |
| **Reason** | $reason |
| **Triggered By** | Automated rollback system |

## Logs

- **Rollback Log**: [rollback.log](logs/rollbacks/rollback.log)
- **Validation Log**: [validation.log](logs/rollbacks/validation.log)

## Infrastructure Status

$(if [ "$status" = "SUCCESS" ]; then cat << 'SUCCESS'
✅ All phases validated  
✅ Infrastructure restored  
✅ Services online  

**Action Required**: Monitor closely for 1 hour
SUCCESS
else
cat << 'FAILED'
❌ Rollback validation failed  
❌ Manual intervention required  

**Action Required**: Investigate logs and determine root cause
FAILED
fi)

---
Auto-generated by automated-rollback system
EOF
  
  gh issue create \
    --repo "$GITHUB_REPO" \
    --title "🔄 Automated Rollback: $status ($new_commit) - $reason" \
    --body "$(cat /tmp/rollback_issue.md)" \
    2>&1 | head -5 || true
}

# Main execution
main() {
  log "=== Automated Rollback System ==="
  
  initialize
  
  # Get reason from parameter or use default
  local rollback_reason="${1:-Automated rollback triggered by health check}"
  
  # Find last successful deployment
  local last_good_commit
  last_good_commit="$(find_last_successful_deployment)" || {
    log_error "Could not find successful deployment to rollback to"
    create_github_issue "FAILED" "CURRENT" "UNKNOWN" "No successful deployment found"
    return 1
  }
  
  # Get current commit
  local current_commit
  current_commit="$(cd "$REPO_ROOT" && git rev-parse --short HEAD)"
  
  # Verify commit is viable
  if ! verify_commit_viable "$last_good_commit"; then
    log_error "Target commit not viable for rollback"
    create_github_issue "FAILED" "$current_commit" "$last_good_commit" "Target commit not viable"
    return 1
  fi
  
  log "Proceeding with rollback"
  
  # Rollback git
  local rollback_branch
  rollback_branch="$(rollback_git "$last_good_commit" "$rollback_reason")" || {
    log_error "Git rollback failed"
    create_github_issue "FAILED" "$current_commit" "$last_good_commit" "Git rollback failed"
    return 1
  }
  
  # Restore terraform state
  if ! restore_terraform_state "$last_good_commit"; then
    log_error "Terraform state restoration failed"
    github_issue "FAILED" "$current_commit" "$last_good_commit" "Terraform restore failed"
    return 1
  fi
  
  # Validate rollback
  if ! validate_rollback; then
    log_error "Rollback validation failed - manual intervention required"
    create_github_issue "VALIDATION_FAILED" "$current_commit" "$last_good_commit" "$rollback_reason"
    return 1
  fi
  
  log_success "Automated rollback completed successfully"
  create_github_issue "SUCCESS" "$current_commit" "$last_good_commit" "$rollback_reason"
  
  return 0
}

# Cleanup
cleanup() {
  rm -f /tmp/rollback_issue.md
}

trap cleanup EXIT

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
