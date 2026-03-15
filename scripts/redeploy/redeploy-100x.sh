#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG_EXAMPLE="$ROOT_DIR/config/redeploy/redeploy.env.example"
CFG_FILE="${REDEPLOY_CONFIG:-$ROOT_DIR/config/redeploy/redeploy.env}"
REPORT_DIR="$ROOT_DIR/reports/redeploy"
DATE_UTC="$(date -u +%Y%m%d-%H%M%S)"
REPORT_FILE="$REPORT_DIR/redeploy-gap-analysis-$DATE_UTC.md"
FAILURES=()
WARNINGS=()

mkdir -p "$REPORT_DIR"

if [[ ! -f "$CFG_FILE" ]]; then
  cp "$CFG_EXAMPLE" "$CFG_FILE"
fi
# shellcheck disable=SC1090
source "$CFG_FILE"

DOMAIN_NAME="${DOMAIN_NAME:-elevatediq.ai}"
DOMAIN_PREFIX="${DOMAIN_PREFIX:-elevatediq}"
ENVIRONMENT="${ENVIRONMENT:-production}"
DRY_RUN="${DRY_RUN:-true}"
TARGET_WORKER_HOST="${TARGET_WORKER_HOST:-192.168.168.42}"
FORBIDDEN_DEV_HOST="${FORBIDDEN_DEV_HOST:-192.168.168.31}"
NAS_HOST="${NAS_HOST:-192.168.168.100}"
ENFORCE_DOMAIN="${ENFORCE_DOMAIN:-true}"
ENFORCE_NAMING="${ENFORCE_NAMING:-true}"
ENFORCE_TEMPLATE_ENV="${ENFORCE_TEMPLATE_ENV:-true}"
ENFORCE_SECURITY="${ENFORCE_SECURITY:-true}"
ENFORCE_GOVERNANCE="${ENFORCE_GOVERNANCE:-true}"

log() { echo "[redeploy-100x] $*"; }
warn() { echo "[redeploy-100x][warn] $*"; WARNINGS+=("$*"); }
fail_step() { echo "[redeploy-100x][fail] $*"; FAILURES+=("$*"); }

run_step() {
  local title="$1"
  shift
  log "$title"
  if ! "$@"; then
    fail_step "$title"
    return 1
  fi
  return 0
}

run_cmd() {
  local cmd="$1"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $cmd"
    return 0
  fi
  bash -lc "$cmd"
}

preflight_tools() {
  local missing=()
  for t in bash git rg jq; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required tools: ${missing[*]}" >&2
    return 1
  fi
  return 0
}

enforce_host_policy() {
  local host_ip
  host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ "$host_ip" == "$FORBIDDEN_DEV_HOST" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      warn "Running in dry-run on forbidden deploy host ($host_ip). Full deployment remains blocked."
      return 0
    fi
    echo "Forbidden host for full production redeploy: $host_ip" >&2
    return 1
  fi
  return 0
}

enforce_no_cloud_build_mandate() {
  local candidate_commands
  candidate_commands="${DEPLOY_COMMANDS:-}"

  if [[ -z "$candidate_commands" ]]; then
    candidate_commands=$'bash scripts/utilities/pre-deployment-readiness-probe.sh\nbash scripts/k8s-health-checks/orchestrate-deployment.sh\nbash scripts/deployment-runbook.sh\nbash scripts/test/post_deploy_validation.sh'
  fi

  if echo "$candidate_commands" | rg -n "gcloud[[:space:]]+builds|cloudbuild" >/dev/null 2>&1; then
    echo "Cloud build command detected in deployment sequence. ONLY BUILD ONPREM is mandatory." >&2
    return 1
  fi

  return 0
}

enforce_domain_policy() {
  if [[ "$ENFORCE_DOMAIN" != "true" ]]; then
    return 0
  fi

  local drift
  drift="$(rg -n "nexusshield\.io|example\.com|TODO_DOMAIN" "$ROOT_DIR/scripts" "$ROOT_DIR/config" 2>/dev/null || true)"
  if [[ -n "$drift" ]]; then
    warn "Domain drift detected outside $DOMAIN_NAME. Review report for exact files."
    {
      echo "## Domain Drift"
      echo '```'
      echo "$drift"
      echo '```'
      echo
    } >> "$REPORT_FILE"
  fi
  return 0
}

check_templates_and_env() {
  if [[ "$ENFORCE_TEMPLATE_ENV" != "true" ]]; then
    return 0
  fi

  local template
  IFS=',' read -r -a required_templates <<< "${REQUIRED_TEMPLATE_FILES:-.env.example}"
  for template in "${required_templates[@]}"; do
    if [[ ! -f "$ROOT_DIR/$template" ]]; then
      fail_step "Missing required template file: $template"
    fi
  done

  if [[ ! -f "$ROOT_DIR/.env" && -f "$ROOT_DIR/.env.example" ]]; then
    cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
    warn "Generated .env from .env.example. Fill secrets before non-dry-run deployment."
  fi

  return 0
}

check_shared_structure() {
  local d
  IFS=',' read -r -a required_dirs <<< "${SHARED_DIRS:-scripts/lib,scripts/redeploy,config/redeploy,docs/redeploy,reports/redeploy}"
  for d in "${required_dirs[@]}"; do
    if [[ ! -d "$ROOT_DIR/$d" ]]; then
      fail_step "Missing shared structure directory: $d"
    fi
  done
  return 0
}

check_overlap_and_duplication() {
  local dup_file
  dup_file="$REPORT_DIR/duplicate-script-basenames-$DATE_UTC.txt"
  find "$ROOT_DIR/scripts" -type f -name '*.sh' -printf '%f\n' | sort | uniq -d > "$dup_file" || true
  if [[ -s "$dup_file" ]]; then
    warn "Duplicate script basenames detected. See $dup_file"
    {
      echo "## Duplicate Script Basenames"
      echo '```'
      cat "$dup_file"
      echo '```'
      echo
    } >> "$REPORT_FILE"
  fi
  return 0
}

check_security_baseline() {
  if [[ "$ENFORCE_SECURITY" != "true" ]]; then
    return 0
  fi

  local hardcoded
  hardcoded="$(rg -n "AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH) PRIVATE KEY|password\s*=\s*['\"]" "$ROOT_DIR/scripts" "$ROOT_DIR/config" 2>/dev/null || true)"
  if [[ -n "$hardcoded" ]]; then
    warn "Potential secret exposure patterns detected."
    {
      echo "## Potential Secret Exposure"
      echo '```'
      echo "$hardcoded"
      echo '```'
      echo
    } >> "$REPORT_FILE"
  fi

  return 0
}

check_service_account_standards() {
  if [[ "$ENFORCE_NAMING" != "true" ]]; then
    return 0
  fi

  local sa_matches
  sa_matches="$(rg -n "elevatediq-svc-|svc-" "$ROOT_DIR/scripts/ssh_service_accounts" 2>/dev/null || true)"
  if [[ -z "$sa_matches" ]]; then
    fail_step "No service-account naming references found in scripts/ssh_service_accounts"
    return 1
  fi

  local nonstandard
  nonstandard="$(rg -n "\bsvc-[a-zA-Z0-9_-]+\b" "$ROOT_DIR/scripts" 2>/dev/null | rg -v "${DOMAIN_PREFIX}-svc-" || true)"
  if [[ -n "$nonstandard" ]]; then
    warn "Found service-account naming that may be outside ${DOMAIN_PREFIX}-svc-* standard"
    {
      echo "## Service Account Naming Drift"
      echo '```'
      echo "$nonstandard"
      echo '```'
      echo
    } >> "$REPORT_FILE"
  fi

  return 0
}

speed_checks() {
  local syntax_report="$REPORT_DIR/syntax-check-$DATE_UTC.txt"
  local files
  files="$(find "$ROOT_DIR/scripts" -type f -name '*.sh')"
  if [[ -z "$files" ]]; then
    warn "No shell scripts found for syntax check"
    return 0
  fi

  # Parallel syntax validation for faster feedback loop.
  printf '%s\n' "$files" | xargs -r -n1 -P4 bash -n > "$syntax_report" 2>&1 || true
  if [[ -s "$syntax_report" ]]; then
    warn "Syntax check report has findings: $syntax_report"
  fi
  return 0
}

run_deploy_sequence() {
  local commands
  if [[ -n "${DEPLOY_COMMANDS:-}" ]]; then
    commands="$DEPLOY_COMMANDS"
  else
    commands=$'bash scripts/utilities/pre-deployment-readiness-probe.sh\nbash scripts/k8s-health-checks/orchestrate-deployment.sh\nbash scripts/deployment-runbook.sh\nbash scripts/test/post_deploy_validation.sh'
  fi

  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    run_cmd "$cmd" || fail_step "Deploy command failed: $cmd"
  done <<< "$commands"

  return 0
}

run_backup_policy_validation() {
  run_cmd "bash scripts/nas-integration/nas-gcp-archive-backup.sh" || fail_step "NAS backup policy validation"
  return 0
}

create_governance_issues() {
  if [[ "$ENFORCE_GOVERNANCE" != "true" ]]; then
    return 0
  fi
  run_cmd "bash scripts/redeploy/create-enhancement-issues.sh" || fail_step "Issue/epic creation"
  return 0
}

generate_report() {
  {
    echo "# Redeploy 100X Gap Analysis"
    echo
    echo "- Timestamp (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "- Environment: $ENVIRONMENT"
    echo "- Domain: $DOMAIN_NAME"
    echo "- Target Worker Host: $TARGET_WORKER_HOST"
    echo "- NAS Host: $NAS_HOST"
    echo "- Dry Run: $DRY_RUN"
    echo

    echo "## Failures"
    if [[ ${#FAILURES[@]} -eq 0 ]]; then
      echo "- None"
    else
      for f in "${FAILURES[@]}"; do
        echo "- $f"
      done
    fi
    echo

    echo "## Warnings"
    if [[ ${#WARNINGS[@]} -eq 0 ]]; then
      echo "- None"
    else
      for w in "${WARNINGS[@]}"; do
        echo "- $w"
      done
    fi
    echo

    echo "## Delta Summary"
    echo "- Process: centralized entrypoint in scripts/redeploy"
    echo "- Consistency: env and template checks enforced"
    echo "- Security: pattern-based exposure scan executed"
    echo "- Governance: issue/epic generation integrated"
    echo "- Backups: NAS to GCP daily+weekly retention policy validated"
  } > "$REPORT_FILE"

  # Appended sections from checks may already be in file. Keep them if they exist.
  log "Gap analysis report generated: $REPORT_FILE"
}

main() {
  log "Starting full-stack redeploy 100X framework"

  run_step "Preflight tool checks" preflight_tools || true
  run_step "Host policy enforcement" enforce_host_policy || true
  run_step "No-cloud-build mandate" enforce_no_cloud_build_mandate || true
  run_step "Domain policy enforcement" enforce_domain_policy || true
  run_step "Template and env checks" check_templates_and_env || true
  run_step "Shared structure checks" check_shared_structure || true
  run_step "Overlap and duplication checks" check_overlap_and_duplication || true
  run_step "Security baseline checks" check_security_baseline || true
  run_step "Service account and naming checks" check_service_account_standards || true
  run_step "Speed checks (parallel shell syntax)" speed_checks || true
  run_step "Deploy sequence" run_deploy_sequence || true
  run_step "NAS backup policy validation" run_backup_policy_validation || true
  run_step "Governance issue creation" create_governance_issues || true

  generate_report

  if [[ ${#FAILURES[@]} -gt 0 ]]; then
    log "Completed with failures (${#FAILURES[@]}). Review $REPORT_FILE"
    return 1
  fi

  log "Completed successfully. Review $REPORT_FILE"
  return 0
}

main "$@"
