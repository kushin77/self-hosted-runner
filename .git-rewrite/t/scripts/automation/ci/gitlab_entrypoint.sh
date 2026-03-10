#!/usr/bin/env bash
set -euo pipefail
# CI entrypoint for GitLab jobs to call PMO scripts safely

LOG_PREFIX="[gitlab_entrypoint]"
echo "$LOG_PREFIX starting with args: $*"

cmd=${1-}

case "$cmd" in
  assignee_enforcer)
    echo "$LOG_PREFIX running assignee enforcer script"
    if [ -x ./scripts/pmo/assignee_enforcer.sh ]; then
      ./scripts/pmo/assignee_enforcer.sh
    else
      echo "$LOG_PREFIX ./scripts/pmo/assignee_enforcer.sh not found or not executable"
      exit 0
    fi
    ;;

  compliance_audit)
    echo "$LOG_PREFIX running compliance audit"
    if [ -f ./scripts/pmo/compliance_checker.py ]; then
      python3 ./scripts/pmo/compliance_checker.py audit-all
    else
      echo "$LOG_PREFIX compliance_checker.py missing"
      exit 0
    fi
    ;;

  auto_close)
    echo "$LOG_PREFIX running auto-close for PR issues"
    if [ -x ./scripts/pmo/auto_close_pr_issues.sh ]; then
      ./scripts/pmo/auto_close_pr_issues.sh
    else
      echo "$LOG_PREFIX auto_close_pr_issues.sh missing"
      exit 0
    fi
    ;;

  milestone_enforcer)
    echo "$LOG_PREFIX running milestone enforcer script"
    if [ -x ./scripts/pmo/milestone_enforcer.sh ]; then
      ./scripts/pmo/milestone_enforcer.sh --open
    else
      echo "$LOG_PREFIX milestone_enforcer.sh missing"
      exit 0
    fi
    ;;

  commit_validator)
    echo "$LOG_PREFIX running commit validator"
    if [ -x ./scripts/pmo/commit_validator.sh ]; then
      ./scripts/pmo/commit_validator.sh
    else
      echo "$LOG_PREFIX commit_validator.sh missing"
      exit 0
    fi
    ;;

  generate_dashboard)
    echo "$LOG_PREFIX generating PMO dashboard"
    if [ -x ./scripts/pmo/generate_dashboard.sh ]; then
      ./scripts/pmo/generate_dashboard.sh
    else
      echo "$LOG_PREFIX generate_dashboard.sh missing"
      exit 0
    fi
    ;;

  session_update)
    note=${2-"Automated CI session update"}
    echo "$LOG_PREFIX adding session update: $note"
    if [ -x ./scripts/pmo/session_tracker.sh ]; then
      ./scripts/pmo/session_tracker.sh update issue "$note" || true
    else
      echo "$LOG_PREFIX session_tracker.sh missing"
      exit 0
    fi
    ;;

  help|--help|-h|"")
    echo "Usage: $0 {assignee_enforcer|session_update <message>}"
    exit 0
    ;;

  *)
    echo "$LOG_PREFIX unknown command: $cmd"
    echo "Usage: $0 {assignee_enforcer|session_update <message>}"
    exit 2
    ;;
esac

echo "$LOG_PREFIX finished"
