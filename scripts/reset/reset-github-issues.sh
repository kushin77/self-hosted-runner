#!/usr/bin/env bash
set -euo pipefail

# Closes existing open issues and creates a fresh enterprise tracking set.
# Requires: gh authenticated

OWNER="kushin77"
REPO="self-hosted-runner"
DOMAIN="${1:-elevatediq.ai}"

ensure_gh() {
  command -v gh >/dev/null 2>&1 || { echo "gh CLI required"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh auth required"; exit 1; }
}

close_open_issues() {
  gh issue list --repo "$OWNER/$REPO" --state open --limit 200 --json number,title | \
    jq -r '.[] | [.number, .title] | @tsv' | while IFS=$'\t' read -r num title; do
      [[ -z "$num" ]] && continue
      gh issue close "$num" --repo "$OWNER/$REPO" --comment "Reset program executed: cloud/on-prem runtime torn down. Rebuild tracking moved to fresh SNC program for domain ${DOMAIN}."
    done
}

create_issue() {
  local title="$1"
  local body="$2"
  gh issue create --repo "$OWNER/$REPO" --title "$title" --body "$body"
}

create_fresh_program_issues() {
  create_issue "Program/Gate0: SNC and governance baseline for ${DOMAIN}" "Define SNC artifacts and governance controls for ${DOMAIN}.\n\nAcceptance:\n- SNC contract committed\n- IAM baseline documented\n- Security baseline documented\n- Go/No-Go gate checklist created"

  create_issue "Program/Gate1: Platform scaffold (no deploy)" "Create Terraform and platform scaffolds only, no resource creation.\n\nAcceptance:\n- Platform folder skeleton committed\n- Module boundaries defined\n- Naming convention enforcement added"

  create_issue "Program/Gate2: Workload deployment process scaffold" "Define deployment workflow scaffolding only for Kubernetes services.\n\nAcceptance:\n- Release flow yaml committed\n- Stage gate checks defined\n- Rollback process documented"

  create_issue "Program/Gate3: Reliability and observability baseline" "Create SLO/SLI, alerting, and runbook scaffolds for go-live readiness.\n\nAcceptance:\n- SLO template committed\n- Alert taxonomy defined\n- Incident runbook skeleton committed"

  create_issue "Program/Gate4: Security and secrets compliance" "Validate secrets-only preservation and least-privilege model for rebuild path.\n\nAcceptance:\n- Secrets inventory checkpointed\n- Access model documented\n- Rotation process scaffolded"

  create_issue "Program/Gate5: Release readiness and cutover" "Prepare enterprise cutover and rollback readiness package.\n\nAcceptance:\n- Cutover checklist committed\n- Rollback drill plan committed\n- Sign-off matrix committed"

  create_issue "Program/Reset Verification: Runtime remains at zero" "Track and verify that runtime stays torn down until rebuild approval.\n\nAcceptance:\n- Weekly verification command set\n- Drift detection checklist\n- Closure criteria defined"
}

main() {
  ensure_gh
  close_open_issues
  create_fresh_program_issues
  echo "GitHub issue reset complete for ${OWNER}/${REPO}"
}

main "$@"
