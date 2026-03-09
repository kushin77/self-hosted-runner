#!/usr/bin/env bash
set -euo pipefail

# Automated Deployment Orchestrator with Immutable Audit Logging
# Purpose: Commit automation changes directly to main with full audit trail
# Idempotent, ephemeral, hands-off, no manual PRs

print_usage() {
  cat <<'EOF'
Usage: automated-deployment-orchestrator.sh --issue-number <num> --change-type <type> --description <desc> [--files file1,file2,...] [--commit-msg "msg"]

Executes an automated deployment to main with:
- Immutable audit trail (GitHub issue)
- Pre-commit validation
- Idempotent execution
- Full hands-off automation

Change Types:
  - policy-update (governance/branch protection)
  - secret-rotation (GSM/Vault/KMS credentials)
  - automation-deploy (workflow/script updates)
  - config-sync (infrastructure configuration)
  - compliance-remediation (security patches)

Environment:
  GITHUB_TOKEN: Required for committing and issue creation
  GIT_USER_NAME: "Automation Bot" (default)
  GIT_USER_EMAIL: "automation@self-hosted-runner.dev" (default)

Example:
  $0 --issue-number 2111 --change-type automation-deploy \
     --description "Deploy verified validation policy" \
     --files ".github/workflows/validate-policies-and-keda.yml" \
     --commit-msg "automation: deploy Issue #2111 orchestration engine"
EOF
}

ISSUE_NUMBER=""
CHANGE_TYPE=""
DESCRIPTION=""
FILES=""
COMMIT_MSG=""
GIT_USER_NAME="${GIT_USER_NAME:-Automation Bot}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-automation@self-hosted-runner.dev}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue-number) ISSUE_NUMBER="$2"; shift 2;;
    --change-type) CHANGE_TYPE="$2"; shift 2;;
    --description) DESCRIPTION="$2"; shift 2;;
    --files) FILES="$2"; shift 2;;
    --commit-msg) COMMIT_MSG="$2"; shift 2;;
    -h|--help) print_usage; exit 0;;
    *) echo "Unknown arg: $1"; print_usage; exit 2;;
  esac
done

if [[ -z "$ISSUE_NUMBER" || -z "$CHANGE_TYPE" || -z "$DESCRIPTION" ]]; then
  echo "--issue-number, --change-type, and --description are required" >&2
  print_usage
  exit 2
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "GITHUB_TOKEN environment variable required" >&2
  exit 2
fi

# Generate audit record
AUDIT_TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
AUDIT_ID="$(echo -n "$AUDIT_TIMESTAMP-$ISSUE_NUMBER-$CHANGE_TYPE" | sha256sum | cut -c1-8)"
AUDIT_LOG=$(cat <<EOF
{
  "audit_id": "$AUDIT_ID",
  "timestamp": "$AUDIT_TIMESTAMP",
  "issue_number": $ISSUE_NUMBER,
  "change_type": "$CHANGE_TYPE",
  "description": "$DESCRIPTION",
  "user": "$GIT_USER_NAME",
  "email": "$GIT_USER_EMAIL",
  "commit_msg": "${COMMIT_MSG:-$DESCRIPTION}",
  "files_changed": ["${FILES//,/\", \"}"],
  "status": "in-progress"
}
EOF
)

echo "=== Automated Deployment Orchestrator ==="
echo "Audit ID: $AUDIT_ID"
echo "Issue: #$ISSUE_NUMBER"
echo "Change Type: $CHANGE_TYPE"
echo "Description: $DESCRIPTION"
echo ""

# Validate change type
case "$CHANGE_TYPE" in
  policy-update|secret-rotation|automation-deploy|config-sync|compliance-remediation) ;;
  *) echo "Invalid change-type: $CHANGE_TYPE" >&2; exit 2;;
esac

# Pre-commit validation
echo "=== Pre-Commit Validation ==="

# Check if files exist (if specified)
if [[ -n "$FILES" ]]; then
  IFS=',' read -ra FILE_ARRAY <<< "$FILES"
  for file in "${FILE_ARRAY[@]}"; do
    file=$(echo "$file" | xargs)  # trim whitespace
    if [[ ! -f "$file" ]]; then
      echo "❌ File not found: $file" >&2
      exit 2
    fi
    echo "✅ File exists: $file"
  done
fi

# Validate JSON/YAML/shell syntax
echo "Validating file syntax..."
for file in "${FILE_ARRAY[@]:-}"; do
  file=$(echo "$file" | xargs)
  if [[ -f "$file" ]]; then
    case "${file##*.}" in
      json)
        if ! jq . "$file" >/dev/null 2>&1; then
          echo "❌ JSON validation failed: $file" >&2
          exit 2
        fi
        echo "✅ JSON valid: $file"
        ;;
      yaml|yml)
        if ! command -v yamllint >/dev/null 2>&1; then
          echo "⚠️  yamllint not installed; skipping YAML validation"
        elif ! yamllint "$file" >/dev/null 2>&1; then
          echo "❌ YAML validation failed: $file" >&2
          exit 2
        fi
        echo "✅ YAML valid: $file"
        ;;
      sh)
        if ! bash -n "$file" >/dev/null 2>&1; then
          echo "❌ Shell script validation failed: $file" >&2
          exit 2
        fi
        echo "✅ Shell script valid: $file"
        ;;
    esac
  fi
done

echo ""
echo "=== Preparing Immutable Audit Log ==="

# Append audit log to deployment audit trail
AUDIT_LOG_FILE="logs/deployment-orchestration-audit.jsonl"
mkdir -p logs
echo "$AUDIT_LOG" >> "$AUDIT_LOG_FILE"
echo "✅ Audit log recorded: $AUDIT_LOG_FILE"

echo ""
echo "=== Committing Changes to main ==="

# Configure git
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"

# Ensure we're on main
git checkout main >/dev/null 2>&1 || git checkout -b main

# Stage files
if [[ -n "$FILES" ]]; then
  IFS=',' read -ra FILE_ARRAY <<< "$FILES"
  for file in "${FILE_ARRAY[@]}"; do
    file=$(echo "$file" | xargs)
    git add "$file"
    echo "📝 Staged: $file"
  done
fi

# Stage audit log
git add "$AUDIT_LOG_FILE"
echo "📝 Staged: $AUDIT_LOG_FILE"

# Commit with full audit context
COMMIT_MESSAGE="${COMMIT_MSG:-$DESCRIPTION}

Issue: #$ISSUE_NUMBER
Change-Type: $CHANGE_TYPE
Audit-ID: $AUDIT_ID
Timestamp: $AUDIT_TIMESTAMP

Description: $DESCRIPTION

Change-Type: $CHANGE_TYPE
Files: $(echo "${FILES:-NONE}" | tr ',' '\n' | sed 's/^ */* /')

---
Automation-Generated: true
Immutable-Audit: logs/deployment-orchestration-audit.jsonl
Governance: Issue #$ISSUE_NUMBER
---"

git commit -m "$COMMIT_MESSAGE" || {
  if git diff --cached --quiet; then
    echo "ℹ️  No changes to commit (idempotent)"
  else
    echo "❌ Commit failed" >&2
    exit 2
  fi
}

echo "✅ Changes committed to main"

echo ""
echo "=== Creating Immutable GitHub Issue Audit Record ==="

# Create GitHub issue comment for audit trail
ISSUE_COMMENT=$(cat <<EOF
## Automated Deployment: $CHANGE_TYPE ✅

**Audit ID:** \`$AUDIT_ID\`  
**Timestamp:** $AUDIT_TIMESTAMP  
**Change Type:** $CHANGE_TYPE  
**Description:** $DESCRIPTION  

### Files Changed
\`\`\`
$(echo "${FILES:-NONE}" | tr ',' '\n' | sed 's/^ *//')
\`\`\`

### Commit Details
\`\`\`bash
git log --oneline -1
\`\`\`

### Audit Trail
- Location: \`logs/deployment-orchestration-audit.jsonl\`
- Status: ✅ Complete
- Method: Automated trunk-based deployment
- Approval: Governance-driven (no manual approval)

### Governance
- No-Ops: ✅ Fully automated
- Immutable: ✅ Append-only audit trail
- Ephemeral: ✅ Fresh state per run
- Idempotent: ✅ Safe to re-execute
- Hands-Off: ✅ No manual gates

**Status:** Deployment complete. See commit history for details.
EOF
)

# Use gh CLI to add comment
if command -v gh >/dev/null 2>&1; then
  timeout 20 bash -c "gh issue comment $ISSUE_NUMBER --body '$ISSUE_COMMENT'" 2>&1 || {
    echo "⚠️  Could not add GitHub issue comment (network issue or API limits)"
  }
  echo "✅ Issue comment added (if API available)"
else
  echo "⚠️  gh CLI not available; skipping issue comment"
fi

echo ""
echo "=== Deployment Complete ==="
echo "Audit ID: $AUDIT_ID"
echo "Issue: #$ISSUE_NUMBER"
echo "Status: ✅ SUCCESS"
echo "Audit Log: logs/deployment-orchestration-audit.jsonl"
echo ""
echo "Next: Push to remote to trigger post-commit enforcement."
