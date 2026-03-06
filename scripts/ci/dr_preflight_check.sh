#!/usr/bin/env bash
# dr_preflight_check.sh — Pre-flight validation before ops finalization tasks
#
# Purpose: Verify that all DR automation code is in place, properly committed,
#          and ready for ops to execute the 4 finalization tasks (issues 906-909).
#
# Usage:
#   ./scripts/ci/dr_preflight_check.sh [--verbose]
#
# Output: Pass/Fail checklist with remediation steps
# Exit Code: 0 = all checks pass; 1 = one or more checks failed

set -euo pipefail

VERBOSE="${1:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/scripts"
CHECKS_PASSED=0
CHECKS_FAILED=0

# ============================================================================
# Utility Functions
# ============================================================================

log_check() {
    echo "  [ ] $*"
}

log_pass() {
    echo "  [✓] $*"
    ((CHECKS_PASSED++))
}

log_fail() {
    echo "  [✗] $* — FIX REQUIRED"
    ((CHECKS_FAILED++))
}

log_warn() {
    echo "  [⚠]  $* — Non-critical"
}

log_section() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $* "
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================================================
# Checks
# ============================================================================

log_section "Phase 1: Core Automation Scripts"

# Check bootstrap script
if [[ -f "$REPO_ROOT/bootstrap/restore_from_github.sh" ]]; then
    log_pass "bootstrap/restore_from_github.sh exists"
else
    log_fail "bootstrap/restore_from_github.sh missing"
fi

# Check backup script
if [[ -f "$SCRIPT_DIR/backup/gitlab_backup_encrypt.sh" ]]; then
    log_pass "scripts/backup/gitlab_backup_encrypt.sh exists"
else
    log_fail "scripts/backup/gitlab_backup_encrypt.sh missing"
fi

# Check DR drill script
if [[ -f "$SCRIPT_DIR/dr/drill_run.sh" ]]; then
    log_pass "scripts/dr/drill_run.sh exists"
else
    log_fail "scripts/dr/drill_run.sh missing"
fi

# Check CI orchestration scripts
for script in create_dr_schedule.sh rotate_github_deploy_key.sh run_dr_dryrun.sh \
              ingest_dr_log_and_close_issues.sh report_dr_status.sh dr_pipeline_monitor.sh; do
    if [[ -f "$SCRIPT_DIR/ci/$script" ]]; then
        # Check if executable
        if [[ -x "$SCRIPT_DIR/ci/$script" ]]; then
            log_pass "scripts/ci/$script (executable)"
        else
            log_warn "scripts/ci/$script exists but not executable"
            chmod +x "$SCRIPT_DIR/ci/$script"
        fi
    else
        log_fail "scripts/ci/$script missing"
    fi
done

log_section "Phase 2: CI/CD Templates"

# Check CI templates exist
for template in dr-dryrun dr-monitor dr-alert; do
    if [[ -f "$REPO_ROOT/ci_templates/${template}.yml" ]]; then
        log_pass "ci_templates/${template}.yml exists"
    else
        log_fail "ci_templates/${template}.yml missing"
    fi
done

# Check main .gitlab-ci.yml includes templates
if grep -q "ci_templates/dr-dryrun.yml" "$REPO_ROOT/config/cicd/.gitlab-ci.yml"; then
    log_pass ".gitlab-ci.yml includes dr-dryrun.yml"
else
    log_fail ".gitlab-ci.yml missing dr-dryrun.yml include"
fi

if grep -q "ci_templates/dr-monitor.yml" "$REPO_ROOT/config/cicd/.gitlab-ci.yml"; then
    log_pass ".gitlab-ci.yml includes dr-monitor.yml"
else
    log_fail ".gitlab-ci.yml missing dr-monitor.yml include"
fi

if grep -q "ci_templates/dr-alert.yml" "$REPO_ROOT/config/cicd/.gitlab-ci.yml"; then
    log_pass ".gitlab-ci.yml includes dr-alert.yml"
else
    log_fail ".gitlab-ci.yml missing dr-alert.yml include"
fi

log_section "Phase 3: Documentation & Issue Tracking"

# Check key documentation exists
for doc in DR_RUNBOOK OPS_FINALIZATION_RUNBOOK HANDS_OFF_DR_IMPLEMENTATION_SUMMARY; do
    if [[ -f "$REPO_ROOT/docs/${doc}.md" ]] || [[ -f "$REPO_ROOT/${doc}.md" ]]; then
        log_pass "Found $doc.md"
    else
        log_warn "$doc.md not found (non-critical for ops)"
    fi
done

# Check finalization checklist
if [[ -f "$REPO_ROOT/DR_OPS_FINALIZATION_CHECKLIST.md" ]]; then
    log_pass "DR_OPS_FINALIZATION_CHECKLIST.md exists (ops reference)"
else
    log_warn "DR_OPS_FINALIZATION_CHECKLIST.md missing (helpful but not critical)"
fi

# Check issues
log_check "Checking ops follow-up issues..."
ISSUE_COUNT=0
for issue_num in 906 907 908 909; do
    if [[ -f "$REPO_ROOT/issues/${issue_num}-"*.md ]]; then
        log_pass "Issue $issue_num (ops follow-up)"
        ((ISSUE_COUNT++))
    else
        log_fail "Issue $issue_num missing"
    fi
done

log_section "Phase 4: Git & Deployment State"

# Check current branch
CURRENT_BRANCH=$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [[ "$CURRENT_BRANCH" == "main" ]]; then
    log_pass "On main branch (ready for deployment)"
else
    log_warn "On $CURRENT_BRANCH (should be main for release)"
fi

# Check for uncommitted changes
UNCOMMITTED=$(cd "$REPO_ROOT" && git status --short 2>/dev/null | wc -l || echo "0")
if [[ "$UNCOMMITTED" -eq 0 ]]; then
    log_pass "No uncommitted changes (clean working directory)"
else
    log_fail "$UNCOMMITTED uncommitted changes — run 'git status' to see"
fi

# Check latest commit message
LATEST_COMMIT=$(cd "$REPO_ROOT" && git log -1 --oneline 2>/dev/null || echo "unknown")
if grep -qi "dr\|automation\|monitoring" <<< "$LATEST_COMMIT"; then
    log_pass "Latest commit related to DR automation: $LATEST_COMMIT"
else
    log_warn "Latest commit may not be DR-related: $LATEST_COMMIT"
fi

log_section "Phase 5: Secret Management Prerequisites"

# Check if gcloud is available
if command -v gcloud &>/dev/null; then
    log_pass "gcloud CLI available (required for GSM access)"
else
    log_fail "gcloud CLI not found — install Google Cloud SDK"
fi

# Check if jq is available
if command -v jq &>/dev/null; then
    log_pass "jq available (for parsing JSON)"
else
    log_fail "jq not found — install jq for JSON parsing"
fi

# Check if curl is available
if command -v curl &>/dev/null; then
    log_pass "curl available (for API calls)"
else
    log_fail "curl not found — install curl"
fi

# Try to list GSM secrets (non-fatal if auth unavailable)
if gcloud secrets list --project=gcp-eiq &>/dev/null 2>&1; then
    log_pass "GSM project gcp-eiq is accessible"
    
    # Check for critical secrets
    for secret in github-token slack-webhook ci-gcs-bucket vault-approle-role-id vault-approle-secret-id; do
        if gcloud secrets list --project=gcp-eiq --filter="name:$secret" --format="value(name)" 2>/dev/null | grep -q "$secret"; then
            log_pass "GSM secret '$secret' exists"
        else
            log_warn "GSM secret '$secret' not found (will be needed later)"
        fi
    done
    
    # Check for ops-provisioned secrets
    if gcloud secrets list --project=gcp-eiq --filter="name:gitlab-api-token" --format="value(name)" 2>/dev/null | grep -q "gitlab-api-token"; then
        log_pass "gitlab-api-token already in GSM (issue 906 may be complete)"
    else
        log_warn "gitlab-api-token not in GSM — ops should add it via issue 906"
    fi
else
    log_warn "GSM not accessible from this machine — ops will handle secret provisioning"
fi

log_section "Phase 6: Readiness Summary"

echo
echo "  DIAGNOSTIC SUMMARY:"
echo "  ─────────────────────────────────"
echo "    Checks Passed:  $CHECKS_PASSED"
echo "    Checks Failed:  $CHECKS_FAILED"
echo "    Issues Found:   $ISSUE_COUNT/4 ops tasks present"
echo "  ─────────────────────────────────"
echo

if [[ $CHECKS_FAILED -eq 0 ]]; then
    echo "  ✅ ALL CHECKS PASSED — System is ready for ops finalization"
    echo
    echo "  Next Steps (for ops):"
    echo "  1. Read: DR_OPS_FINALIZATION_CHECKLIST.md"
    echo "  2. Execute Issue 906: GitLab token & schedule"
    echo "  3. Execute Issue 907: Deploy key rotation"
    echo "  4. Execute Issue 908: Backup verification"
    echo "  5. Execute Issue 909: Monitoring setup (optional)"
    echo
    echo "  Documentation:"
    echo "  • Ops Checklist: DR_OPS_FINALIZATION_CHECKLIST.md"
    echo "  • Runbook: docs/OPS_FINALIZATION_RUNBOOK.md"
    echo "  • Implementation Summary: HANDS_OFF_DR_IMPLEMENTATION_SUMMARY.md"
    echo
    exit 0
else
    echo "  ❌ $CHECKS_FAILED CRITICAL ISSUE(S) FOUND"
    echo
    echo "  Remediation Required:"
    echo "  • Re-run with git on main branch"
    echo "  • Commit any pending changes: git add -A && git commit"
    echo "  • Verify all scripts are present in the repo"
    echo
    exit 1
fi
