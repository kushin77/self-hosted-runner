#!/usr/bin/env bash
# Stale Branch Cleanup Automation
# Purpose: Remove merged feature branches to maintain repository cleanliness
# Status: Hands-off automation (fully autonomous, no manual intervention required)
# Controlled by: Issue #755

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "${SCRIPT_DIR}/../../../" && pwd)")"

LOG_FILE="${PROJECT_ROOT}/stale-branch-cleanup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
}

echo -e "${BLUE}🧹 Stale Branch Cleanup Automation${NC}" | tee "$LOG_FILE"
echo "=======================================" | tee -a "$LOG_FILE"
echo "Repository: ${PROJECT_ROOT}" | tee -a "$LOG_FILE"
echo "Log File: ${LOG_FILE}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Verify git is available
if ! command -v git &> /dev/null; then
    log_error "git not found in PATH"
    exit 1
fi

cd "$PROJECT_ROOT"

# Ensure we're on main branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    log_warn "Not on main branch (current: $CURRENT_BRANCH), switching..."
    git checkout main || { log_error "Failed to switch to main"; exit 1; }
fi

# Fetch latest changes
log_info "Fetching latest changes from origin..."
git fetch --prune origin || { log_error "Failed to fetch"; exit 1; }
log_success "Fetched latest changes"

# Count merged branches
MERGED_COUNT=$(git branch --merged main | grep -E "(feat/|fix/|hotfix/)" | wc -l)
log_info "Found $MERGED_COUNT merged branches to clean up"

if [[ $MERGED_COUNT -eq 0 ]]; then
    log_success "No merged branches to clean up"
    exit 0
fi

# List merged branches before deletion
log_info "Merged branches to delete:"
git branch --merged main | grep -E "(feat/|fix/|hotfix/)" | tee -a "$LOG_FILE" | sed 's/^/  - /'

# Delete merged branches
DELETED=0
FAILED=0

echo "" | tee -a "$LOG_FILE"
log_info "Starting branch deletion..."

while IFS= read -r branch; do
    branch=$(echo "$branch" | xargs)  # trim whitespace
    if [[ -z "$branch" ]]; then
        continue
    fi
    
    if git branch -d "$branch" 2>/dev/null || git branch -D "$branch" 2>/dev/null; then
        log_success "Deleted: $branch"
        ((DELETED++))
    else
        log_warn "Could not delete (may have non-merged commits): $branch"
        ((FAILED++))
    fi
done < <(git branch --merged main | grep -E "(feat/|fix/|hotfix/)" || true)

# Summary
echo "" | tee -a "$LOG_FILE"
echo "=======================================" | tee -a "$LOG_FILE"
log_info "Cleanup Summary:"
log_success "Deleted: $DELETED branches"
if [[ $FAILED -gt 0 ]]; then
    log_warn "Skipped: $FAILED branches (may have unmerged commits)"
fi

# Verify result
REMAINING=$(git branch | grep -E "(feat/|fix/|hotfix/)" | wc -l || true)
log_info "Remaining feature branches: $REMAINING"

# Generate cleanup report
REPORT_FILE="${PROJECT_ROOT}/stale-branch-cleanup-report-$(date +%Y%m%d-%H%M%S).json"
cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "completed",
  "deleted_count": $DELETED,
  "skipped_count": $FAILED,
  "remaining_feature_branches": $REMAINING,
  "log_file": "$LOG_FILE",
  "scope": "Merged feature branches (feat/*, fix/*, hotfix/*)"
}
EOF

log_success "Report written to: $REPORT_FILE"
log_success "All cleanup operations completed"

exit 0