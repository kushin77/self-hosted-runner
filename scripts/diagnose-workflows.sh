#!/bin/bash
#
# Comprehensive workflow health diagnostics and prioritized remediation
# Focus: Get critical workflows to 100% functional
#

set -euo pipefail

WORKFLOWS_DIR=".github/workflows"
REPORT_FILE="WORKFLOW_REMEDIATION_PRIORITY.md"

echo "# Workflow Remediation Priority & Status Report" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Generated:** $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Critical path workflows
CRITICAL_WORKFLOWS=(
    "00-master-router.yml"
    "01-alacarte-deployment.yml"
    "terraform-auto-apply.yml"
    "elasticache-apply-gsm.yml"
    "deploy-cloud-credentials.yml"
    "secrets-health.yml"
    "system-status-aggregator.yml"
)

echo "## 🚨 Critical Path Workflows (Blocks All Other Workflows)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

for wf in "${CRITICAL_WORKFLOWS[@]}"; do
    wf_path="$WORKFLOWS_DIR/$wf"
    if [[ -f "$wf_path" ]]; then
        if python3 -c "import yaml; yaml.safe_load(open('$wf_path'))" 2>/dev/null; then
            echo "| ✅ $wf | SYNTAX OK | No action needed |" >> "$REPORT_FILE"
        else
            ERROR=$(python3 -c "import yaml; yaml.safe_load(open('$wf_path'))" 2>&1 | tail -1 | head -c 80)
            echo "| ❌ $wf | SYNTAX ERROR | $ERROR... |" >> "$REPORT_FILE"
        fi
    else
        echo "| ❌ $wf | NOT FOUND | File missing |" >> "$REPORT_FILE"
    fi
done

echo "" >> "$REPORT_FILE"
echo "## 📊 All Workflows Status Summary" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Count statistics
TOTAL_WORKFLOWS=$(find "$WORKFLOWS_DIR" -name "*.yml" -type f ! -name "*.bak" | wc -l)
VALID_WORKFLOWS=0
ERROR_WORKFLOWS=0

while IFS= read -r wf; do
    if python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>/dev/null; then
        ((VALID_WORKFLOWS++))
    else
        ((ERROR_WORKFLOWS++))
    fi
done < <(find "$WORKFLOWS_DIR" -name "*.yml" -type f ! -name "*.bak")

SUCCESS_RATE=$((VALID_WORKFLOWS * 100 / TOTAL_WORKFLOWS))

echo "| Metric | Value |" >> "$REPORT_FILE"
echo "|---|---|" >> "$REPORT_FILE"
echo "| Total Workflows | $TOTAL_WORKFLOWS |" >> "$REPORT_FILE"
echo "| Valid (Syntax OK) | $VALID_WORKFLOWS |" >> "$REPORT_FILE"
echo "| With Errors | $ERROR_WORKFLOWS |" >> "$REPORT_FILE"
echo "| Success Rate | $SUCCESS_RATE% |" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "## 🔴 Workflows with YAML Errors ($ERROR_WORKFLOWS)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Workflow | Status | Severity |" >> "$REPORT_FILE"
echo "|---|---|---|" >> "$REPORT_FILE"

find "$WORKFLOWS_DIR" -name "*.yml" -type f ! -name "*.bak" | sort | while read wf; do
    if ! python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>/dev/null; then
        wf_name=$(basename "$wf")
        
        # Determine severity
        if [[ "$wf_name" == *"master-router"* ]] || [[ "$wf_name" == *"alacarte-deployment"* ]]; then
            SEVERITY="🔴 CRITICAL"
        elif [[ "$wf_name" == *"terraform"* ]] || [[ "$wf_name" == *"deploy"* ]] || [[ "$wf_name" == *"secret"* ]]; then
            SEVERITY="🟠 HIGH"
        else
            SEVERITY="🟡 MEDIUM"
        fi
        
        ERROR=$(python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>&1 | grep -o "error.*" | head -1 || echo "Unknown")
        echo "| $wf_name | ❌ Parse Error | $SEVERITY |" >> "$REPORT_FILE"
    fi
done

echo "" >> "$REPORT_FILE"
echo "## ✅ Workflows with Valid Syntax ($VALID_WORKFLOWS)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

VALID_LIST=$(find "$WORKFLOWS_DIR" -name "*.yml" -type f ! -name "*.bak" | while read wf; do
    if python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>/dev/null; then
        basename "$wf"
    fi
done | sort)

echo "\`\`\`" >> "$REPORT_FILE"
echo "$VALID_LIST" | head -20
echo "\`\`\`" >> "$REPORT_FILE"
echo "(and $(echo "$VALID_LIST" | wc -l) total)" >> "$REPORT_FILE"

echo "" >> "$REPORT_FILE"
echo "## 🎯 Remediation Strategy" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Phase 1 (Critical):** Fix master-router and alacarte-deployment workflows" >> "$REPORT_FILE"
echo "**Phase 2 (High):** Fix terraform and deployment related workflows" >> "$REPORT_FILE"
echo "**Phase 3 (Medium):** Disable problematic triggers, keep workflow_dispatch on others" >> "$REPORT_FILE"
echo "**Phase 4 (Auto-heal):** Self-healing system monitors and fixes remaining issues" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

cat "$REPORT_FILE"

exit 0
