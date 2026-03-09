#!/bin/bash
# Discover and report on deployment fields across the repository
# Identifies which fields need provisioning and their current state
#
# Usage: discover-deployment-fields.sh [--output=json|markdown|text]

set -euo pipefail

OUTPUT_FORMAT="${1:-text}"  # json, markdown, text
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Required deployment fields with metadata
declare -A FIELDS=(
    [VAULT_ADDR]="Vault server URL"
    [VAULT_ROLE]="Vault GitHub Actions role"
    [AWS_ROLE_TO_ASSUME]="AWS IAM role ARN for OIDC"
    [GCP_WORKLOAD_IDENTITY_PROVIDER]="GCP Workload Identity Federation provider"
)

# Placeholder patterns to identify
PLACEHOLDER_PATTERNS=(
    "example\.com"
    "placeholder"
    "EXAMPLE"
    "PLACEHOLDER"
    "YOUR_"
    "\*\*\*"
    "123456789012"
)

# ============================================================================
# DISCOVERY FUNCTIONS
# ============================================================================

check_env_variable() {
    local field="$1"
    if [ -n "${!field:-}" ]; then
        echo "environment"
        return 0
    fi
    return 1
}

check_github_secret() {
    local field="$1"
    if ! command -v gh &>/dev/null; then
        return 1
    fi
    
    local secret_value=$(gh secret list --json name,createdAt --jq ".[] | select(.name==\"$field\") | .createdAt" 2>/dev/null || echo "")
    if [ -n "$secret_value" ]; then
        echo "github-secret"
        return 0
    fi
    return 1
}

check_env_file() {
    local field="$1"
    
    for envfile in .env .env.local .env.deployment .env.production; do
        if [ -f "$REPO_ROOT/$envfile" ] && grep -q "^${field}=" "$REPO_ROOT/$envfile"; then
            echo "env-file:$envfile"
            return 0
        fi
    done
    return 1
}

check_systemd_environment() {
    local field="$1"
    if [ -f /etc/systemd/system/daemon-scheduler.service.d/deployment-fields.conf ]; then
        if grep -q "Environment=\"${field}=" /etc/systemd/system/daemon-scheduler.service.d/deployment-fields.conf; then
            echo "systemd-dropins"
            return 0
        fi
    fi
    return 1
}

get_field_value() {
    local field="$1"
    
    # Try environment first
    if [ -n "${!field:-}" ]; then
        echo "${!field}"
        return 0
    fi
    
    # Try GitHub secret
    if command -v gh &>/dev/null; then
        local secret=$(gh secret list --json name 2>/dev/null | grep -q "$field" && echo "REDACTED" || echo "")
        if [ -n "$secret" ]; then
            echo "REDACTED (GitHub secret)"
            return 0
        fi
    fi
    
    # Try env files
    for envfile in .env .env.local .env.deployment .env.production; do
        if [ -f "$REPO_ROOT/$envfile" ]; then
            local value=$(grep "^${field}=" "$REPO_ROOT/$envfile" | cut -d'=' -f2- || echo "")
            if [ -n "$value" ]; then
                echo "$value"
                return 0
            fi
        fi
    done
    
    echo ""
    return 1
}

is_placeholder() {
    local value="$1"
    
    for pattern in "${PLACEHOLDER_PATTERNS[@]}"; do
        if echo "$value" | grep -qE "$pattern"; then
            return 0
        fi
    done
    return 1
}

find_field_references() {
    local field="$1"
    local count=0
    
    # Search in scripts
    count=$((count + $(grep -r "\${$field}" "$REPO_ROOT/scripts" 2>/dev/null | wc -l)))
    
    # Search in workflows
    count=$((count + $(grep -r "\${{ env.$field }}" "$REPO_ROOT/.github/workflows" 2>/dev/null | wc -l)))
    
    # Search in documentation
    count=$((count + $(grep -r "$field" "$REPO_ROOT/docs" "$REPO_ROOT/*.md" 2>/dev/null | grep -v "UPDATE THIS" | wc -l)))
    
    echo "$count"
}

# ============================================================================
# OUTPUT FORMATTING
# ============================================================================

output_text() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  DEPLOYMENT FIELDS DISCOVERY REPORT                            ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    local all_found=0
    local all_placeholder=0
    local all_missing=0
    
    for field in "${!FIELDS[@]}"; do
        local description="${FIELDS[$field]}"
        local value
        local source
        local is_placeholder=false
        
        if value=$(get_field_value "$field"); then
            source=$(check_env_variable "$field" || check_github_secret "$field" || check_env_file "$field" || check_systemd_environment "$field" || echo "unknown")
            
            if is_placeholder "$value"; then
                is_placeholder=true
                ((all_placeholder++))
            else
                ((all_found++))
            fi
        else
            ((all_missing++))
        fi
        
        # Format status
        local status
        if [ "$is_placeholder" = "true" ]; then
            status="⚠️  PLACEHOLDER"
        elif [ -z "$value" ]; then
            status="❌ MISSING"
        else
            status="✅ CONFIGURED"
        fi
        
        local refs=$(find_field_references "$field")
        
        echo "📋 $field"
        echo "   Description: $description"
        echo "   Status: $status"
        echo "   Source: ${source:-N/A}"
        echo "   References: $refs locations in codebase"
        echo ""
    done
    
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  SUMMARY                                                        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo "  Configured: $all_found"
    echo "  Placeholders: $all_placeholder"
    echo "  Missing: $all_missing"
    echo ""
    
    if [ $all_missing -gt 0 ] || [ $all_placeholder -gt 0 ]; then
        echo "⚠️  Action Required:"
        echo "   Run: scripts/auto-provision-deployment-fields.sh"
        echo "   Or manually update: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions"
        echo ""
    fi
}

output_json() {
    local fields_json="{"
    local first=true
    
    for field in "${!FIELDS[@]}"; do
        local value=$(get_field_value "$field" || echo "")
        local source=$(check_env_variable "$field" || check_github_secret "$field" || check_env_file "$field" || check_systemd_environment "$field" || echo "unknown")
        local is_placeholder
        
        if [ -n "$value" ] && is_placeholder "$value"; then
            is_placeholder="true"
        else
            is_placeholder="false"
        fi
        
        if [ "$first" = false ]; then
            fields_json+=","
        fi
        
        fields_json+="\"$field\":{\"description\":\"${FIELDS[$field]}\",\"has_value\":$([ -n "$value" ] && echo true || echo false),\"is_placeholder\":$is_placeholder,\"source\":\"$source\"}"
        first=false
    done
    
    fields_json+="}"
    echo "$fields_json"
}

output_markdown() {
    echo "# Deployment Fields Discovery Report"
    echo ""
    echo "**Generated:** $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo ""
    echo "## Fields Status"
    echo ""
    echo "| Field | Status | Source | References |"
    echo "|-------|--------|--------|-----------|"
    
    for field in "${!FIELDS[@]}"; do
        local value=$(get_field_value "$field" || echo "")
        local source=$(check_env_variable "$field" || check_github_secret "$field" || check_env_file "$field" || check_systemd_environment "$field" || echo "N/A")
        local is_placeholder
        local status
        
        if [ -z "$value" ]; then
            status="❌ Missing"
        elif [ -n "$value" ] && is_placeholder "$value"; then
            status="⚠️  Placeholder"
        else
            status="✅ Configured"
        fi
        
        local refs=$(find_field_references "$field")
        
        echo "| \`$field\` | $status | $source | $refs |"
    done
    
    echo ""
    echo "## Actions Required"
    echo ""
    echo "If any fields are missing or placeholder values:"
    echo ""
    echo "\`\`\`bash"
    echo "# Option 1: Auto-provision (recommended)"
    echo "./scripts/auto-provision-deployment-fields.sh"
    echo ""
    echo "# Option 2: Manual update via GitHub"
    echo "# Visit: https://github.com/kushin77/self-hosted-runner/settings/secrets/actions"
    echo "\`\`\`"
}

# ============================================================================
# MAIN
# ============================================================================

case "$OUTPUT_FORMAT" in
    json)
        output_json
        ;;
    markdown)
        output_markdown
        ;;
    text)
        output_text
        ;;
    *)
        echo "Unknown output format: $OUTPUT_FORMAT"
        exit 1
        ;;
esac
