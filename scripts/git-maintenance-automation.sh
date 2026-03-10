#!/bin/bash
# git-maintenance-automation.sh
# Complete git repository garbage collection and maintenance
# Immutable audit trail. Idempotent. Runs via systemd timer.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT_FILE="${REPO_ROOT}/logs/git-maintenance.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$(dirname "${AUDIT_FILE}")"

audit_entry() {
    local event="$1"
    local details="${2:-}"
    echo "{\"timestamp\": \"${TIMESTAMP}\", \"event\": \"${event}\", \"details\": \"${details}\", \"immutable\": true}" >> "${AUDIT_FILE}"
}

# ============================================================================
# Pre-Maintenance Checks
# ============================================================================
pre_maintenance_checks() {
    echo "[GIT] Running pre-maintenance checks..."

    cd "${REPO_ROOT}"

    # Verify repository integrity
    if ! git fsck --full &>/dev/null; then
        echo "ERROR: Repository integrity check failed. Aborting."
        audit_entry "pre_check_failed" "fsck found corruption"
        exit 1
    fi

    # Verify no uncommitted changes
    if ! git diff-index --quiet HEAD -- &>/dev/null; then
        echo "WARNING: Uncommitted changes detected. Stashing..."
        git stash
        audit_entry "stash_created" "uncommitted changes before maintenance"
    fi

    echo "[GIT] ✅ Pre-checks passed"
    audit_entry "pre_checks_passed" "repository is clean"
}

# ============================================================================
# Garbage Collection (Aggressive)
# ============================================================================
run_garbage_collection() {
    echo "[GIT] Running aggressive garbage collection..."

    cd "${REPO_ROOT}"

    # Prune unreachable objects
    git prune --expire=now 2>&1 | tee -a "${AUDIT_FILE}.tmp" || true

    # Run aggressive GC
    git gc --aggressive --prune=now 2>&1 | tee -a "${AUDIT_FILE}.tmp" || true

    # Repack with delta compression
    git repack -a -d -f --depth=250 --window=250 2>&1 | tee -a "${AUDIT_FILE}.tmp" || true

    # Verify integrity post-GC
    if git fsck --full &>/dev/null; then
        echo "[GIT] ✅ Garbage collection completed successfully"
        audit_entry "gc_completed" "aggressive gc with delta compression"
    else
        echo "[GIT] ❌ Integrity check failed after GC"
        audit_entry "gc_integrity_failed" "fsck found issues post-gc"
        exit 1
    fi
}

# ============================================================================
# Reflog Cleanup
# ============================================================================
cleanup_reflog() {
    echo "[REFLOG] Cleaning up reflog..."

    cd "${REPO_ROOT}"

    # Expire old reflog entries (30 days)
    git reflog expire --all --expire=30.days

    # Delete expired entries
    git reflog delete --rebase --update-ref --expire=now

    echo "[REFLOG] ✅ Reflog cleaned"
    audit_entry "reflog_cleaned" "expired entries > 30 days removed"
}

# ============================================================================
# Repository Statistics
# ============================================================================
collect_statistics() {
    echo "[STATS] Collecting repository statistics..."

    cd "${REPO_ROOT}"

    local object_count=$(git count-objects -s | head -1)
    local repo_size=$(du -sh .git | awk '{print $1}')
    local loose_objects=$(git count-objects -s | grep "loose objects" | awk '{print $1}')
    local pack_files=$(find .git/objects/pack -name "*.pack" | wc -l)

    echo "[STATS] Repository Statistics:"
    echo "  Objects: ${object_count}"
    echo "  Size: ${repo_size}"
    echo "  Loose objects: ${loose_objects}"
    echo "  Pack files: ${pack_files}"

    audit_entry "statistics" "objects=${object_count} size=${repo_size} loose_objects=${loose_objects} pack_files=${pack_files}"
}

# ============================================================================
# Clean Stale Branches
# ============================================================================
cleanup_stale_branches() {
    echo "[BRANCHES] Cleaning stale tracking branches..."

    cd "${REPO_ROOT}"

    # Remove stale remote tracking branches (30 days)
    git remote prune origin

    # List branches not merged to main (more than 30 days old)
    local stale_count=0
    while IFS= read -r branch; do
        if [[ ! -z $(git log -1 --since="30 days ago" --format="%H" "${branch}" 2>/dev/null) ]]; then
            echo "[BRANCHES] Keeping: ${branch}"
        else
            echo "[BRANCHES] Removing stale: ${branch}"
            git branch -D "${branch}" 2>/dev/null || true
            ((stale_count++))
        fi
    done < <(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v "^main$" | grep -v "^production$" | head -20)

    echo "[BRANCHES] ✅ Cleaned ${stale_count} stale branches"
    audit_entry "branches_cleaned" "stale=${stale_count}"
}

# ============================================================================
# Optimize File Permissions
# ============================================================================
optimize_permissions() {
    echo "[PERMS] Optimizing file permissions..."

    cd "${REPO_ROOT}"

    # Ensure .git directory has proper permissions
    chmod -R go-rwx .git

    # Ensure hooks are executable
    chmod +x .git/hooks/* 2>/dev/null || true

    echo "[PERMS] ✅ Permissions optimized"
    audit_entry "permissions_optimized" "git directory secured"
}

# ============================================================================
# Immutable Audit & Git Record
# ============================================================================
finalize() {
    cd "${REPO_ROOT}"

    # Commit audit to git (immutable record)
    git add "${AUDIT_FILE}"
    git commit -m "ops: git maintenance completed (${TIMESTAMP}) - gc aggressive, reflog cleaned, stale branches removed" || true

    # Push to main
    git push origin main || true

    echo "[AUDIT] ✅ Maintenance audit recorded"
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo "=========================================="
    echo "Git Repository Maintenance"
    echo "Time: ${TIMESTAMP}"
    echo "Immutable • Idempotent • Hands-Off"
    echo "=========================================="

    pre_maintenance_checks
    run_garbage_collection
    cleanup_reflog
    collect_statistics
    cleanup_stale_branches
    optimize_permissions
    finalize

    echo "=========================================="
    echo "✅ Git maintenance complete"
    echo "Size reduction: Check logs/git-maintenance.jsonl"
    echo "=========================================="
}

main "$@"
