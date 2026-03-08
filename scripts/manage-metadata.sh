#!/bin/bash
#
# manage-metadata.sh - Core metadata management tool
#
# CRUD operations for managing workflows, scripts, secrets, and dependencies
#

set -euo pipefail

METADATA_DIR="metadata"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Error handling
# ============================================================================
error() {
    echo -e "${RED}✗ ERROR: $1${NC}" >&2
    exit 1
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

info() {
    echo -e "${BLUE}→ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# ============================================================================
# Validation functions
# ============================================================================
validate_json() {
    local file="$1"
    if ! jq empty "$file" 2>/dev/null; then
        error "Invalid JSON in $file"
    fi
}

validate_id_format() {
    local id="$1"
    if [[ ! "$id" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ${#id} -gt 2 ]]; then
        error "Invalid ID format: $id (must be lowercase alphanumeric with hyphens)"
    fi
}

validate_risk_level() {
    local level="$1"
    case "$level" in
        CRITICAL|HIGH|MEDIUM|LOW) return 0 ;;
        *) error "Invalid risk level: $level (must be CRITICAL, HIGH, MEDIUM, or LOW)" ;;
    esac
}

validate_owner_exists() {
    local owner="$1"
    if ! jq -e --arg owner "$owner" '.owners | has($owner)' "$METADATA_DIR/owners.json" >/dev/null 2>&1; then
        warn "Owner '$owner' not found in owners.json"
        return 1
    fi
    return 0
}

# ============================================================================
# Helper functions
# ============================================================================
ensure_metadata_dir() {
    if [[ ! -d "$METADATA_DIR" ]]; then
        info "Creating metadata directory structure..."
        mkdir -p "$METADATA_DIR"/templates
        mkdir -p "$METADATA_DIR"/schemas
        cp "$SCRIPT_DIR/../metadata/templates"/* "$METADATA_DIR/templates/" 2>/dev/null || true
    fi
}

init_metadata_files() {
    ensure_metadata_dir
    
    # Initialize items.json if missing
    if [[ ! -f "$METADATA_DIR/items.json" ]]; then
        cat > "$METADATA_DIR/items.json" << 'EOF'
{
  "version": "1.0.0",
  "last_updated": "2026-03-08T00:00:00Z",
  "workflows": [],
  "scripts": [],
  "secrets": []
}
EOF
    fi
    
    # Initialize dependencies.json if missing
    if [[ ! -f "$METADATA_DIR/dependencies.json" ]]; then
        cat > "$METADATA_DIR/dependencies.json" << 'EOF'
{
  "version": "1.0.0",
  "last_updated": "2026-03-08T00:00:00Z",
  "dependencies": []
}
EOF
    fi
    
    # Initialize owners.json if missing
    if [[ ! -f "$METADATA_DIR/owners.json" ]]; then
        cat > "$METADATA_DIR/owners.json" << 'EOF'
{
  "version": "1.0.0",
  "last_updated": "2026-03-08T00:00:00Z",
  "owners": {
    "platform-team": {
      "email": "platform@company.com",
      "slack": "#platform",
      "members": []
    }
  }
}
EOF
    fi
    
    # Initialize change-log.json if missing
    if [[ ! -f "$METADATA_DIR/change-log.json" ]]; then
        cat > "$METADATA_DIR/change-log.json" << 'EOF'
{
  "version": "1.0.0",
  "changes": []
}
EOF
    fi
}

log_change() {
    local action="$1"
    local item_id="$2"
    local details="$3"
    
    local entry=$(jq -n \
        --arg ts "$TIMESTAMP" \
        --arg action "$action" \
        --arg item "$item_id" \
        --arg details "$details" \
        --arg user "${USER:-unknown}" \
        '{timestamp: $ts, action: $action, item_id: $item, details: $details, user: $user}')
    
    jq ".changes += [$entry]" "$METADATA_DIR/change-log.json" > "$METADATA_DIR/change-log.json.tmp"
    mv "$METADATA_DIR/change-log.json.tmp" "$METADATA_DIR/change-log.json"
}

# ============================================================================
# Add operations
# ============================================================================
cmd_add_workflow() {
    local id="$1"
    local path="$2"
    local owner="$3"
    local risk_level="${4:-MEDIUM}"
    
    validate_id_format "$id"
    validate_risk_level "$risk_level"
    validate_owner_exists "$owner" || warn "Unknown owner: $owner"
    
    if jq -e --arg id "$id" '.workflows[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        error "Workflow '$id' already exists"
    fi
    
    [[ ! -f "$path" ]] && error "Workflow file not found: $path"
    
    local workflow=$(jq -n \
        --arg id "$id" \
        --arg name "$id" \
        --arg path "$path" \
        --arg owner "$owner" \
        --arg risk "$risk_level" \
        --arg ts "$TIMESTAMP" \
        '{
            id: $id,
            name: $name,
            path: $path,
            owner: $owner,
            risk_level: $risk,
            critical: ($risk == "CRITICAL"),
            created: $ts,
            last_modified: $ts,
            status: "active",
            dependencies: []
        }')
    
    jq ".workflows += [$workflow]" "$METADATA_DIR/items.json" > "$METADATA_DIR/items.json.tmp"
    mv "$METADATA_DIR/items.json.tmp" "$METADATA_DIR/items.json"
    
    log_change "add_workflow" "$id" "Added workflow: $path, owner: $owner, risk: $risk_level"
    success "Added workflow: $id"
}

cmd_add_script() {
    local id="$1"
    local path="$2"
    local owner="$3"
    local risk_level="${4:-MEDIUM}"
    
    validate_id_format "$id"
    validate_risk_level "$risk_level"
    validate_owner_exists "$owner" || warn "Unknown owner: $owner"
    
    if jq -e --arg id "$id" '.scripts[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        error "Script '$id' already exists"
    fi
    
    [[ ! -f "$path" ]] && error "Script file not found: $path"
    
    local permissions=$(stat -f "%A" "$path" 2>/dev/null || stat -c "%a" "$path" 2>/dev/null)
    local hash=$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1)
    
    local script=$(jq -n \
        --arg id "$id" \
        --arg name "$id" \
        --arg path "$path" \
        --arg owner "$owner" \
        --arg risk "$risk_level" \
        --arg perms "$permissions" \
        --arg hash "$hash" \
        --arg ts "$TIMESTAMP" \
        '{
            id: $id,
            name: $name,
            path: $path,
            owner: $owner,
            risk_level: $risk,
            created: $ts,
            last_modified: $ts,
            permissions: $perms,
            hash: $hash,
            status: "active",
            dependencies: []
        }')
    
    jq ".scripts += [$script]" "$METADATA_DIR/items.json" > "$METADATA_DIR/items.json.tmp"
    mv "$METADATA_DIR/items.json.tmp" "$METADATA_DIR/items.json"
    
    log_change "add_script" "$id" "Added script: $path, owner: $owner, risk: $risk_level"
    success "Added script: $id"
}

cmd_add_secret() {
    local id="$1"
    local type="$2"
    local owner="$3"
    
    validate_id_format "$id"
    validate_owner_exists "$owner" || warn "Unknown owner: $owner"
    
    if jq -e --arg id "$id" '.secrets[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        error "Secret '$id' already exists"
    fi
    
    local secret=$(jq -n \
        --arg id "$id" \
        --arg name "$id" \
        --arg type "$type" \
        --arg owner "$owner" \
        --arg ts "$TIMESTAMP" \
        '{
            id: $id,
            name: $name,
            type: $type,
            owner: $owner,
            risk_level: "CRITICAL",
            created: $ts,
            last_modified: $ts,
            rotation_period: 90,
            requires_mfa: true,
            status: "active",
            required_by: []
        }')
    
    jq ".secrets += [$secret]" "$METADATA_DIR/items.json" > "$METADATA_DIR/items.json.tmp"
    mv "$METADATA_DIR/items.json.tmp" "$METADATA_DIR/items.json"
    
    log_change "add_secret" "$id" "Added secret: $type, owner: $owner"
    success "Added secret: $id"
}

cmd_add_dependency() {
    local from="$1"
    local to="$2"
    local type="${3:-depends_on}"
    
    # Verify both items exist
    local from_exists=false
    local to_exists=false
    
    if jq -e --arg id "$from" '.workflows[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        from_exists=true
    fi
    if jq -e --arg id "$from" '.scripts[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        from_exists=true
    fi
    
    if jq -e --arg id "$to" '.workflows[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        to_exists=true
    fi
    if jq -e --arg id "$to" '.scripts[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        to_exists=true
    fi
    if jq -e --arg id "$to" '.secrets[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        to_exists=true
    fi
    
    [[ "$from_exists" == "false" ]] && error "Source item not found: $from"
    [[ "$to_exists" == "false" ]] && error "Target item not found: $to"
    
    # Check for self-dependency
    if [[ "$from" == "$to" ]]; then
        error "Circular dependency detected: $from depends on itself"
    fi
    
    local dependency=$(jq -n \
        --arg from "$from" \
        --arg to "$to" \
        --arg type "$type" \
        --arg ts "$TIMESTAMP" \
        '{
            from: $from,
            to: $to,
            type: $type,
            required: true,
            added: $ts
        }')
    
    jq ".dependencies += [$dependency]" "$METADATA_DIR/dependencies.json" > "$METADATA_DIR/dependencies.json.tmp"
    mv "$METADATA_DIR/dependencies.json.tmp" "$METADATA_DIR/dependencies.json"
    
    log_change "add_dependency" "$from" "Added dependency: $from → $to ($type)"
    success "Added dependency: $from → $to"
}

# ============================================================================
# Update operations
# ============================================================================
cmd_update() {
    local item_id="$1"
    local field="$2"
    local value="$3"
    
    # Try to find and update in workflows
    if jq -e --arg id "$item_id" '.workflows[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        jq --arg id "$item_id" --arg field "$field" --arg value "$value" \
            '(.workflows[] | select(.id == $id) | .[$field]) = ($value | if test("^[0-9]+$") then tonumber else . end) | .last_updated = "'$TIMESTAMP'"' \
            "$METADATA_DIR/items.json" > "$METADATA_DIR/items.json.tmp"
        mv "$METADATA_DIR/items.json.tmp" "$METADATA_DIR/items.json"
        log_change "update" "$item_id" "Updated field '$field' to '$value'"
        success "Updated workflow: $item_id"
        return 0
    fi
    
    # Try scripts
    if jq -e --arg id "$item_id" '.scripts[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        jq --arg id "$item_id" --arg field "$field" --arg value "$value" \
            '(.scripts[] | select(.id == $id) | .[$field]) = ($value | if test("^[0-9]+$") then tonumber else . end) | .last_updated = "'$TIMESTAMP'"' \
            "$METADATA_DIR/items.json" > "$METADATA_DIR/items.json.tmp"
        mv "$METADATA_DIR/items.json.tmp" "$METADATA_DIR/items.json"
        log_change "update" "$item_id" "Updated field '$field' to '$value'"
        success "Updated script: $item_id"
        return 0
    fi
    
    # Try secrets
    if jq -e --arg id "$item_id" '.secrets[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        jq --arg id "$item_id" --arg field "$field" --arg value "$value" \
            '(.secrets[] | select(.id == $id) | .[$field]) = ($value | if test("^[0-9]+$") then tonumber else . end) | .last_updated = "'$TIMESTAMP'"' \
            "$METADATA_DIR/items.json" > "$METADATA_DIR/items.json.tmp"
        mv "$METADATA_DIR/items.json.tmp" "$METADATA_DIR/items.json"
        log_change "update" "$item_id" "Updated field '$field' to '$value'"
        success "Updated secret: $item_id"
        return 0
    fi
    
    error "Item not found: $item_id"
}

# ============================================================================
# List/Query operations
# ============================================================================
cmd_list() {
    local type="${1:-all}"
    local filter="${2:-}"
    
    case "$type" in
        workflows|all)
            echo -e "${CYAN}=== Workflows ===${NC}"
            jq -r '.workflows[] | "\(.id) [\(.risk_level)] - \(.owner)"' "$METADATA_DIR/items.json"
            [[ "$type" != "all" ]] && return 0
            ;;
    esac
    
    case "$type" in
        scripts|all)
            [[ "$type" == "all" ]] && echo ""
            echo -e "${CYAN}=== Scripts ===${NC}"
            jq -r '.scripts[] | "\(.id) [\(.risk_level)] - \(.owner)"' "$METADATA_DIR/items.json"
            [[ "$type" != "all" ]] && return 0
            ;;
    esac
    
    case "$type" in
        secrets|all)
            [[ "$type" == "all" ]] && echo ""
            echo -e "${CYAN}=== Secrets ===${NC}"
            jq -r '.secrets[] | "\(.id) [\(.risk_level)] - \(.owner)"' "$METADATA_DIR/items.json"
            ;;
    esac
}

cmd_search() {
    local query="$1"
    
    echo -e "${CYAN}Search results for: $query${NC}\n"
    
    # Search workflows
    jq --arg q "$query" '.workflows[] | select(.id | contains($q) or .description | contains($q) or .path | contains($q))' "$METADATA_DIR/items.json" | \
        jq -r '"[WORKFLOW] \(.id)"'
    
    # Search scripts
    jq --arg q "$query" '.scripts[] | select(.id | contains($q) or .path | contains($q))' "$METADATA_DIR/items.json" | \
        jq -r '"[SCRIPT] \(.id)"'
    
    # Search secrets
    jq --arg q "$query" '.secrets[] | select(.id | contains($q) or .name | contains($q))' "$METADATA_DIR/items.json" | \
        jq -r '"[SECRET] \(.id)"'
}

cmd_export() {
    local format="${1:-json}"
    
    case "$format" in
        json)
            jq '.' "$METADATA_DIR/items.json"
            ;;
        csv)
            echo "ID,Type,Owner,RiskLevel,Status"
            jq -r '.workflows[] | "\(.id),workflow,\(.owner),\(.risk_level),\(.status)"' "$METADATA_DIR/items.json"
            jq -r '.scripts[] | "\(.id),script,\(.owner),\(.risk_level),\(.status)"' "$METADATA_DIR/items.json"
            jq -r '.secrets[] | "\(.id),secret,\(.owner),\(.risk_level),\(.status)"' "$METADATA_DIR/items.json"
            ;;
        *)
            error "Unknown format: $format (json, csv)"
            ;;
    esac
}

# ============================================================================
# Remove operations
# ============================================================================
cmd_remove() {
    local item_id="$1"
    local reason="${2:-No reason provided}"
    
    # Try to remove from workflows
    if jq -e --arg id "$item_id" '.workflows[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        jq --arg id "$item_id" 'del(.workflows[] | select(.id == $id))' "$METADATA_DIR/items.json" > "$METADATA_DIR/items.json.tmp"
        mv "$METADATA_DIR/items.json.tmp" "$METADATA_DIR/items.json"
        log_change "remove" "$item_id" "Removed workflow: $reason"
        success "Removed workflow: $item_id"
        return 0
    fi
    
    # Try scripts
    if jq -e --arg id "$item_id" '.scripts[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        jq --arg id "$item_id" 'del(.scripts[] | select(.id == $id))' "$METADATA_DIR/items.json" > "$METADATA_DIR/items.json.tmp"
        mv "$METADATA_DIR/items.json.tmp" "$METADATA_DIR/items.json"
        log_change "remove" "$item_id" "Removed script: $reason"
        success "Removed script: $item_id"
        return 0
    fi
    
    # Try secrets
    if jq -e --arg id "$item_id" '.secrets[] | select(.id == $id)' "$METADATA_DIR/items.json" >/dev/null 2>&1; then
        jq --arg id "$item_id" 'del(.secrets[] | select(.id == $id))' "$METADATA_DIR/items.json" > "$METADATA_DIR/items.json.tmp"
        mv "$METADATA_DIR/items.json.tmp" "$METADATA_DIR/items.json"
        log_change "remove" "$item_id" "Removed secret: $reason"
        success "Removed secret: $item_id"
        return 0
    fi
    
    error "Item not found: $item_id"
}

# ============================================================================
# Main command handler
# ============================================================================
main() {
    init_metadata_files
    
    if [[ $# -eq 0 ]]; then
        cat << 'EOF'
Usage: manage-metadata.sh <command> [options]

Commands:
  add-workflow <id> <path> <owner> [risk-level]    Add workflow
  add-script <id> <path> <owner> [risk-level]      Add script
  add-secret <id> <type> <owner>                   Add secret
  add-dependency <from> <to> <type>                Add dependency
  
  update <id> <field> <value>                      Update item field
  remove <id> [reason]                             Remove item
  
  list [type] [filter]                             List items (workflows|scripts|secrets|all)
  search <query>                                   Search items
  
  export <format>                                  Export data (json|csv)
  
  validate                                         Validate all metadata
  deps                                             Show dependency analysis

Examples:
  manage-metadata.sh add-workflow deploy-prod .github/workflows/deploy.yml platform-team HIGH
  manage-metadata.sh add-dependency deploy-prod aws-credentials requires
  manage-metadata.sh list workflows
  manage-metadata.sh search "production"
  manage-metadata.sh update deploy-prod risk_level CRITICAL
  manage-metadata.sh export csv > inventory.csv
EOF
        exit 0
    fi
    
    case "$1" in
        add-workflow)
            shift
            cmd_add_workflow "$@"
            ;;
        add-script)
            shift
            cmd_add_script "$@"
            ;;
        add-secret)
            shift
            cmd_add_secret "$@"
            ;;
        add-dependency)
            shift
            cmd_add_dependency "$@"
            ;;
        update)
            shift
            cmd_update "$@"
            ;;
        remove)
            shift
            cmd_remove "$@"
            ;;
        list)
            shift
            cmd_list "$@"
            ;;
        search)
            shift
            cmd_search "$@"
            ;;
        export)
            shift
            cmd_export "$@"
            ;;
        validate)
            "$SCRIPT_DIR/validate-metadata.sh"
            ;;
        deps)
            "$SCRIPT_DIR/visualize-dependencies.sh"
            ;;
        *)
            error "Unknown command: $1"
            ;;
    esac
}

main "$@"
