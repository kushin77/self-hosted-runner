#!/bin/bash
################################################################################
# 🔍 DEPLOYMENT COMPONENT DETECTION
#
# Analyzes git changes to determine which components/services need rebuilding
# Supports three strategies:
#   1. FULL  - Always rebuild everything (default, maximum safety)
#   2. SMART - Analyze changed files and rebuild affected components only
#   3. TAGS  - Use commit message tags to specify components
#
# Smart Detection Rules:
#   - Changes to scripts/deploy* or deploy-*.sh → Full stack rebuild
#   - Changes to services/* → Rebuild affected service + dependencies
#   - Changes to configs/* → Rebuild configs and affected services
#   - Changes to tests/* → Rebuild affected service tests only
#   - Changes to docs/* → No deployment (docs-only changes)
#
# Tag-Based Detection (in commit message):
#   [DEPLOY:full]        - Full stack rebuild
#   [DEPLOY:service-auth] - Rebuild specific service
#   [DEPLOY:components]  - Specify multiple: [DEPLOY:auth,api,monitoring]
#
# Usage:
#   source scripts/triggers/detect-component-changes.sh
#   detect_components_smart "main" "HEAD"
#   
#   Or directly:
#   bash scripts/triggers/detect-component-changes.sh main HEAD
#
# Output:
#   Prints JSON-formatted component list to stdout
#   Examples:
#     {"strategy":"full","components":["all"]}
#     {"strategy":"smart","components":["auth","api"]}
#     {"strategy":"tags","components":["monitoring"]}
#
################################################################################

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly DETECTION_STRATEGY="${DETECTION_STRATEGY:-full}"  # full|smart|tags

# Component dependency map
declare -A COMPONENT_DEPS=(
    [auth]="core,secrets"
    [api]="core,auth,monitoring"
    [monitoring]="core,timers"
    [timers]="core,monitoring"
    [secrets]="core"
    [core]=""
)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Get files changed between two commits
get_changed_files() {
    local base_ref="$1"
    local head_ref="$2"
    
    if [[ "$base_ref" == "0000000000000000000000000000000000000000" ]]; then
        # Initial commit - all files are "changed"
        git ls-tree -r --name-only "$head_ref" 2>/dev/null || echo ""
    else
        git diff --name-only "$base_ref..$head_ref" 2>/dev/null || echo ""
    fi
}

# Extract deploy tags from commit message
extract_deploy_tags() {
    local commit_ref="$1"
    
    local commit_msg
    commit_msg=$(git log -1 --format=%B "$commit_ref" 2>/dev/null || echo "")
    
    # Look for [DEPLOY:component] or [DEPLOY:component1,component2] patterns
    if [[ "$commit_msg" =~ \[DEPLOY:([^\]]+)\] ]]; then
        local tag="${BASH_REMATCH[1]}"
        # Handle both comma-separated and single components
        echo "$tag" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    fi
}

# Expand component to include dependencies
expand_component_deps() {
    local component="$1"
    local -a visited=()
    local -a queue=("$component")
    
    while [[ ${#queue[@]} -gt 0 ]]; do
        local current="${queue[0]}"
        queue=("${queue[@]:1}")
        
        # Skip if already visited
        if [[ " ${visited[@]} " =~ " $current " ]]; then
            continue
        fi
        
        visited+=("$current")
        
        # Add dependencies to queue
        if [[ -n "${COMPONENT_DEPS[$current]:-}" ]]; then
            local deps="${COMPONENT_DEPS[$current]}"
            for dep in ${deps//,/ }; do
                if [[ -n "$dep" && ! " ${visited[@]} " =~ " $dep " ]]; then
                    queue+=("$dep")
                fi
            done
        fi
    done
    
    # Return deduplicated array
    printf '%s\n' "${visited[@]}" | sort -u
}

# =============================================================================
# DETECTION STRATEGIES
# =============================================================================

# Strategy 1: Full rebuild (always rebuild everything)
detect_components_full() {
    log_debug "Using FULL detection strategy: rebuilding all components"
    echo '"strategy":"full","components":["all"]'
}

# Strategy 2: Smart detection based on changed files
detect_components_smart() {
    local base_ref="$1"
    local head_ref="$2"
    
    log_debug "Using SMART detection strategy"
    
    local changed_files
    changed_files=$(get_changed_files "$base_ref" "$head_ref")
    
    if [[ -z "$changed_files" ]]; then
        log_debug "No changed files detected"
        echo '"strategy":"smart","components":[]'
        return 0
    fi
    
    local -a components=()
    
    # Check deployment scripts - trigger full rebuild
    if echo "$changed_files" | grep -qE '(deploy-|scripts/deploy|\.deploy\.sh|deployment\.sh)'; then
        log_debug "Deployment scripts changed - triggering full rebuild"
        echo '"strategy":"smart","components":["all"]'
        return 0
    fi
    
    # Check for service changes
    if echo "$changed_files" | grep -qE '^services/auth/'; then
        components+=(auth)
    fi
    
    if echo "$changed_files" | grep -qE '^services/api/'; then
        components+=(api)
    fi
    
    if echo "$changed_files" | grep -qE '^services/monitoring/'; then
        components+=(monitoring)
    fi
    
    if echo "$changed_files" | grep -qE '^config/'; then
        if [[ ${#components[@]} -eq 0 ]]; then
            # Config-only changes
            components+=(core)
        fi
    fi
    
    if echo "$changed_files" | grep -qE '^scripts/systemd/'; then
        components+=(timers)
    fi
    
    # Check for docs-only changes
    if [[ ${#components[@]} -eq 0 ]] && echo "$changed_files" | grep -qE '^(docs/|README|CHANGELOG)'; then
        log_debug "Documentation-only changes - no deployment needed"
        echo '"strategy":"smart","components":[]'
        return 0
    fi
    
    # If nothing specifically matched but files changed, do full rebuild for safety
    if [[ ${#components[@]} -eq 0 ]]; then
        log_debug "Unable to determine affected components - triggering full rebuild"
        echo '"strategy":"smart","components":["all"]'
        return 0
    fi
    
    # Expand components with dependencies
    local -a expanded=()
    for comp in "${components[@]}"; do
        mapfile -t deps < <(expand_component_deps "$comp")
        expanded+=("${deps[@]}")
    done
    
    # Deduplicate and output
    local unique_comps
    unique_comps=$(printf '%s\n' "${expanded[@]}" | sort -u | paste -sd ',' -)
    
    log_debug "Smart detection identified components: $unique_comps"
    
    # Format as JSON array
    local json_comps
    json_comps=$(printf '%s\n' "${expanded[@]}" | sort -u | jq -R . | jq -s .)
    
    echo "\"strategy\":\"smart\",\"components\":$json_comps"
}

# Strategy 3: Tag-based detection from commit message
detect_components_tags() {
    local commit_ref="$1"
    
    log_debug "Using TAGS detection strategy"
    
    local -a components
    mapfile -t components < <(extract_deploy_tags "$commit_ref")
    
    if [[ ${#components[@]} -eq 0 ]]; then
        log_debug "No [DEPLOY:*] tags found in commit message"
        echo '"strategy":"tags","components":[]'
        return 0
    fi
    
    # Handle "full" keyword
    if [[ " ${components[@]} " =~ " full " ]]; then
        echo '"strategy":"tags","components":["all"]'
        return 0
    fi
    
    # Expand components with dependencies
    local -a expanded=()
    for comp in "${components[@]}"; do
        if [[ -n "$comp" ]]; then
            mapfile -t deps < <(expand_component_deps "$comp")
            expanded+=("${deps[@]}")
        fi
    done
    
    # Deduplicate and output
    local json_comps
    json_comps=$(printf '%s\n' "${expanded[@]}" | sort -u | jq -R . | jq -s .)
    
    log_debug "Tags detection identified components: $json_comps"
    
    echo "\"strategy\":\"tags\",\"components\":$json_comps"
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

main() {
    local base_ref="${1:-}"
    local head_ref="${2:-HEAD}"
    
    # Validate inputs
    if [[ -z "$base_ref" ]]; then
        log_debug "No base ref provided, assuming 'origin/main'"
        base_ref="origin/main"
    fi
    
    log_debug "Component detection: base=$base_ref head=$head_ref strategy=$DETECTION_STRATEGY"
    
    # Output JSON format: {"strategy":"...", "components": [...]}
    echo -n "{"
    
    case "$DETECTION_STRATEGY" in
        full)
            detect_components_full
            ;;
        smart)
            detect_components_smart "$base_ref" "$head_ref"
            ;;
        tags)
            detect_components_tags "$head_ref"
            ;;
        *)
            log_debug "Unknown strategy: $DETECTION_STRATEGY, using full rebuild"
            detect_components_full
            ;;
    esac
    
    echo "}"
}

# =============================================================================
# SCRIPT ENTRY
# =============================================================================

# Only run if being executed as a script (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
