#!/usr/bin/env bash
# Hands-Off Automation System Health Dashboard
# Purpose: Real-time visibility into workflow status, recent runs, and system health
# Usage: ./scripts/health-dashboard.sh [--watch] [--json]

set -euo pipefail

REPO="kushin77/self-hosted-runner"
WORKFLOWS=(
  "security-audit.yml"
  "auto-ingest-trigger.yml"
  "verify-secrets-and-diagnose.yml"
  "dr-smoke-test.yml"
  "auto-activation-retry.yml"
)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
WATCH=false
JSON_OUTPUT=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --watch) WATCH=true; shift ;;
    --json) JSON_OUTPUT=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Function to format status with color
format_status() {
  local status=$1
  case $status in
    success) echo -e "${GREEN}✅ success${NC}" ;;
    failure) echo -e "${RED}❌ failure${NC}" ;;
    completed) echo -e "${GREEN}✅ completed${NC}" ;;
    queued) echo -e "${YELLOW}⏳ queued${NC}" ;;
    in_progress) echo -e "${BLUE}🔄 in_progress${NC}" ;;
    *) echo "$status" ;;
  esac
}

# Function to get workflow status
get_workflow_status() {
  local workflow=$1
  gh run list \
    --workflow "$workflow" \
    --repo "$REPO" \
    --limit 1 \
    --json number,status,conclusion,createdAt,updatedAt \
    2>/dev/null || echo "[]"
}

# Function to get last 24 hours metrics
get_24h_metrics() {
  local workflow=$1
  gh run list \
    --workflow "$workflow" \
    --repo "$REPO" \
    --limit 100 \
    --json status,conclusion,createdAt \
    2>/dev/null || echo "[]"
}

# Function to calculate success rate
calculate_success_rate() {
  local workflow=$1
  local metrics
  metrics=$(get_24h_metrics "$workflow")
  
  if [ -z "$metrics" ] || [ "$metrics" = "[]" ]; then
    echo "N/A"
    return
  fi
  
  local total_runs
  local successful_runs
  total_runs=$(echo "$metrics" | jq 'length')
  successful_runs=$(echo "$metrics" | jq '[.[] | select(.conclusion == "success")] | length')
  
  if [ "$total_runs" -eq 0 ]; then
    echo "N/A"
  else
    local rate=$((successful_runs * 100 / total_runs))
    echo "${rate}%"
  fi
}

# Main dashboard function
show_dashboard() {
  clear
  
  echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║     Hands-Off Automation System — Health Dashboard             ║${NC}"
  echo -e "${BLUE}║     $(date '+%Y-%m-%d %H:%M:%S UTC')                                  ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  # System Status
  echo -e "${BLUE}📊 System Status${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check if repo is accessible
  if gh repo view "$REPO" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Repository${NC}: Accessible"
  else
    echo -e "${RED}❌ Repository${NC}: Unreachable"
    exit 1
  fi
  
  # Total open issues
  local open_issues
  open_issues=$(gh issue list --state open --repo "$REPO" --limit 1 2>/dev/null | wc -l)
  echo -e "${YELLOW}📋 Open Issues${NC}: $open_issues"
  
  # Open PRs
  local open_prs
  open_prs=$(gh pr list --state open --repo "$REPO" --limit 1 2>/dev/null | wc -l)
  echo -e "${YELLOW}🔀 Open PRs${NC}: $open_prs"
  
  echo ""
  echo -e "${BLUE}🚀 Workflow Status${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Workflow statuses
  for workflow in "${WORKFLOWS[@]}"; do
    local status_data
    status_data=$(get_workflow_status "$workflow")
    
    if [ -z "$status_data" ] || [ "$status_data" = "[]" ]; then
      echo -e "${YELLOW}⚠️  ${workflow}${NC}: No recent runs"
      continue
    fi
    
    local run_id
    local status
    local conclusion
    local created_at
    
    run_id=$(echo "$status_data" | jq -r '.[0].number // "N/A"')
    status=$(echo "$status_data" | jq -r '.[0].status // "N/A"')
    conclusion=$(echo "$status_data" | jq -r '.[0].conclusion // "pending"')
    created_at=$(echo "$status_data" | jq -r '.[0].createdAt // "N/A"')
    
    # Determine display status
    local display_status
    if [ "$conclusion" != "null" ] && [ "$conclusion" != "null" ]; then
      display_status=$(format_status "$conclusion")
    else
      display_status=$(format_status "$status")
    fi
    
    # Calculate time ago
    local time_ago
    if command -v date &> /dev/null; then
      local created_epoch
      created_epoch=$(date -d "$created_at" +%s 2>/dev/null || echo "0")
      local now_epoch
      now_epoch=$(date +%s)
      local diff=$((now_epoch - created_epoch))
      
      if [ "$diff" -lt 60 ]; then
        time_ago="${diff}s ago"
      elif [ "$diff" -lt 3600 ]; then
        time_ago="$((diff / 60))m ago"
      elif [ "$diff" -lt 86400 ]; then
        time_ago="$((diff / 3600))h ago"
      else
        time_ago="$((diff / 86400))d ago"
      fi
    else
      time_ago="N/A"
    fi
    
    printf "%-40s [#%-4s] %s  (%s)\n" \
      "${workflow}" \
      "$run_id" \
      "$display_status" \
      "$time_ago"
  done
  
  echo ""
  echo -e "${BLUE}📈 24-Hour Success Rates${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Success rates
  for workflow in "${WORKFLOWS[@]}"; do
    local rate
    rate=$(calculate_success_rate "$workflow")
    printf "%-40s %s\n" "$workflow" "$rate"
  done
  
  echo ""
  echo -e "${BLUE}🔐 Critical Issue Status${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check critical issues
  local blocking_issues
  blocking_issues=$(gh issue list \
    --state open \
    --label "blocking" \
    --repo "$REPO" \
    --limit 5 \
    --json number,title 2>/dev/null)
  
  if [ -z "$blocking_issues" ] || [ "$blocking_issues" = "[]" ]; then
    echo -e "${GREEN}✅ No blocking issues${NC}"
  else
    echo -e "${RED}⚠️  Blocking Issues Found:${NC}"
    echo "$blocking_issues" | jq -r '.[] | "  #\(.number): \(.title)"'
  fi
  
  echo ""
  echo -e "${BLUE}🔍 Recent Deployment Activity${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Last 5 commits
  git log --oneline -5 2>/dev/null | while read -r commit_info; do
    echo "  $commit_info"
  done
  
  echo ""
  echo -e "${BLUE}📚 Quick Links${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🎯 Activation Status:     https://github.com/$REPO/issues/1239"
  echo "  📊 Phase 6 Dashboard:     https://github.com/$REPO/issues/1267"
  echo "  📖 Operator Playbook:     $(pwd)/HANDS_OFF_OPERATOR_PLAYBOOK.md"
  echo "  🔐 CI/CD Governance:      $(pwd)/CI_CD_GOVERNANCE_GUIDE.md"
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  
  if [ "$WATCH" = true ]; then
    echo "Refreshing in 10 seconds (Press Ctrl+C to exit)..."
    sleep 10
  fi
}

# Show JSON output if requested
show_json_output() {
  local json_data="{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"workflows\": ["
  
  local first=true
  for workflow in "${WORKFLOWS[@]}"; do
    if [ "$first" = false ]; then
      json_data="${json_data},"
    fi
    first=false
    
    local status_data
    status_data=$(get_workflow_status "$workflow")
    json_data="${json_data} {\"workflow\": \"$workflow\", \"status\": $status_data}"
  done
  
  json_data="${json_data}]}"
  echo "$json_data" | jq .
}

# Main execution
if [ "$JSON_OUTPUT" = true ]; then
  show_json_output
else
  if [ "$WATCH" = true ]; then
    while true; do
      show_dashboard
    done
  else
    show_dashboard
  fi
fi
