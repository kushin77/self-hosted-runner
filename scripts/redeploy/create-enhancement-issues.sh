#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG_FILE="${REDEPLOY_CONFIG:-$ROOT_DIR/config/redeploy/redeploy.env}"
OUT_DIR="$ROOT_DIR/reports/redeploy"
mkdir -p "$OUT_DIR"

if [[ -f "$CFG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CFG_FILE"
fi

REPO_OWNER="${REPO_OWNER:-kushin77}"
REPO_NAME="${REPO_NAME:-self-hosted-runner}"
EPIC_TITLE="${GITHUB_EPIC_TITLE:-[EPIC] 100X Redeploy and Go-Live Readiness}"
LABELS_RAW="${GITHUB_LABELS:-governance,redeploy,go-live,automation}"
IFS=',' read -r -a LABELS <<< "$LABELS_RAW"

log() { echo "[issues] $*"; }

have_gh=false
if command -v gh >/dev/null 2>&1; then
  have_gh=true
fi

have_token=false
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  have_token=true
fi

create_with_gh() {
  local title="$1"
  local body_file="$2"
  local labels_csv
  labels_csv="$(IFS=,; echo "${LABELS[*]}")"
  if ! gh issue create --repo "$REPO_OWNER/$REPO_NAME" --title "$title" --body-file "$body_file" --label "$labels_csv"; then
    gh issue create --repo "$REPO_OWNER/$REPO_NAME" --title "$title" --body-file "$body_file"
  fi
}

create_with_token() {
  local title="$1"
  local body_file="$2"
  "$ROOT_DIR/scripts/utilities/create_github_issue.sh" --title "$title" --body-file "$body_file"
}

write_issue_body() {
  local file="$1"
  local title="$2"
  local objective="$3"
  local acceptance="$4"

  cat > "$file" <<EOF
# $title

## Objective
$objective

## Acceptance Criteria
$acceptance

## Notes
- Domain standard: elevatediq.ai
- Naming standard: elevatediq-<service>-<env>
- Deployment must be idempotent and fully script-driven
EOF
}

ensure_gh_labels() {
  local label
  for label in "${LABELS[@]}"; do
    if ! gh label list --repo "$REPO_OWNER/$REPO_NAME" --limit 200 | awk '{print $1}' | grep -qx "$label"; then
      gh label create "$label" --repo "$REPO_OWNER/$REPO_NAME" --description "Auto-created by redeploy governance automation" --color "1d76db" || true
    fi
  done
}

EPIC_FILE="$OUT_DIR/epic-100x-redeploy.md"
cat > "$EPIC_FILE" <<'EOF'
# EPIC: 100X Redeploy and Go-Live Readiness

## Objective
Drive a full-stack, repeatable, secure, and fast redeploy standard that is operationally deterministic and validated daily.

## Scope
- Reinforcement, speed, consistency, security, overlap elimination, enforcement, governance
- Service account hardening and naming standard tied to elevatediq.ai
- Full go-live review, gap/delta tracking, and issue-based governance
- NAS backup policy: daily incremental, weekly full, 30-day retention, stale weekly cleanup

## Success Metrics
- Redeploy can run from one script with zero manual edits
- Full stack validation passes post-redeploy
- Governance issues/epic maintained in GitHub
- Backup policy continuously validated
EOF

if [[ "$have_gh" == true || "$have_token" == true ]]; then
  if [[ "$have_gh" == true ]]; then
    ensure_gh_labels || true
  fi
  log "Creating epic issue in GitHub"
  if [[ "$have_gh" == true ]]; then
    create_with_gh "$EPIC_TITLE" "$EPIC_FILE" || true
  else
    create_with_token "$EPIC_TITLE" "$EPIC_FILE" || true
  fi
else
  log "No GitHub auth detected. Writing issue files only under $OUT_DIR"
fi

# 19 requirements mapped as trackable issues
issue_titles=(
  "Reinforce redeploy process gates"
  "Speed-up deployment path and caching"
  "Standardize env vars and templates"
  "Security hardening enforcement"
  "Overlap and duplication reduction"
  "Policy enforcement guardrails"
  "Governance automation and reporting"
  "Service account normalization"
  "Domain naming standardization (elevatediq.ai)"
  "Optimization pass for stack deployment"
  "Go-live tomorrow full-stack review"
  "Redeployment best practices codification"
  "Git flow automation: merge/push/delete"
  "Clean rebuild automation baseline"
  "Delta and gap analysis automation"
  "GitHub epics/issues lifecycle automation"
  "Daily rebuild operational plan"
  "NAS/cache/monitoring/redis/db optimization"
  "NAS to GCP archive backup policy enforcement"
)

issue_objectives=(
  "Make redeploy workflow deterministic with strict preflight and postflight checks."
  "Reduce deployment cycle time with parallel validation and cache-aware operations."
  "Ensure env-driven configuration and template-based generation across the stack."
  "Apply mandatory security gates before and after deployment."
  "Detect and remove overlapping scripts and duplicate operational pathways."
  "Add machine-enforced policy checks for domain, naming, and structure."
  "Provide governance artifacts and ongoing status reporting in GitHub."
  "Normalize service account naming, lifecycle, and least-privilege controls."
  "Enforce elevatediq.ai as canonical domain standard and prefix conventions."
  "Tune deployment and runtime path for reliability and performance."
  "Conduct full go-live readiness review with checklists and measurable criteria."
  "Define idempotent, rollback-safe, and auditable redeployment best practices."
  "Automate branch merge to main, push, and branch cleanup workflow."
  "Make clean environment rebuild repeatable and low effort."
  "Generate recurring delta and gap reports with owner mapping."
  "Automatically maintain epic and linked issue progression."
  "Design and validate a daily rebuild cadence after issue closure."
  "Leverage NAS, cache, monitoring, Redis, and DB integration for speed and resilience."
  "Guarantee daily incremental and weekly full backups to GCP with retention cleanup."
)

issue_acceptance=(
  "- One-command runbook exists\n- Pre/post validations pass\n- Failure report generated"
  "- Time-to-redeploy is measured\n- Parallel checks enabled\n- Cache utilization report produced"
  "- Missing env vars fail fast\n- Templates generate config\n- No hardcoded domain drift"
  "- Security scans integrated\n- Secret hygiene checks pass\n- Least privilege validated"
  "- Duplicate basenames report created\n- Consolidation plan approved"
  "- Policy gate script blocks non-compliant runs\n- Exceptions are auditable"
  "- Epic dashboard updated\n- Status report published weekly"
  "- Naming follows elevatediq-svc-*\n- Rotation and access model documented"
  "- Domain references validated\n- Non-compliant references listed"
  "- Runtime/infra bottlenecks identified\n- Optimizations implemented"
  "- Full checklist completed\n- Residual risks documented"
  "- Best-practice guide committed\n- Rollback steps tested"
  "- Script handles merge/push/delete\n- Safety checks for main branch included"
  "- Rebuild succeeds from clean state\n- No manual edits required"
  "- Delta report generated per run\n- Gap severity and owners assigned"
  "- Issues are created/updated automatically\n- Traceability maintained"
  "- Daily rebuild script and schedule implemented\n- Output archived"
  "- NAS/cache/monitoring/redis/db checks pass\n- SLA metrics captured"
  "- Incremental and weekly full backups verified\n- Retention cleanup validated"
)

for i in "${!issue_titles[@]}"; do
  n=$((i + 1))
  body_file="$OUT_DIR/issue-$(printf "%02d" "$n").md"
  title="[100X-$(printf "%02d" "$n")] ${issue_titles[$i]}"
  write_issue_body "$body_file" "$title" "${issue_objectives[$i]}" "${issue_acceptance[$i]}"

  if [[ "$have_gh" == true || "$have_token" == true ]]; then
    if [[ "$have_gh" == true ]]; then
      create_with_gh "$title" "$body_file" || true
    else
      create_with_token "$title" "$body_file" || true
    fi
  fi
done

log "Issue and epic artifacts prepared in $OUT_DIR"
