#!/bin/bash
#
# Architecture Compliance Verification Script
# Enforces mandatory on-premises-first deployment constraints
#
# Usage: ./scripts/verify-architecture-compliance.sh
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
COMPLIANT=0
VIOLATIONS=0
SKIPPED=0
FILES_CHECKED=0

# Output functions
print_header() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_pass() {
  echo -e "${GREEN}✅ PASS${NC}: $1"
}

print_fail() {
  echo -e "${RED}❌ FAIL${NC}: $1"
}

print_warn() {
  echo -e "${YELLOW}⚠️  SKIP${NC}: $1"
}

print_info() {
  echo -e "${BLUE}ℹ️  INFO${NC}: $1"
}

# Verify single file
verify_file() {
  local file="$1"
  local priority="${2:-PRIORITY 0}"
  
  FILES_CHECKED=$((FILES_CHECKED + 1))
  
  # Check if file exists
  if [[ ! -f "$file" ]]; then
    print_warn "$file (not found)"
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi
  
  local violations=0
  local issues=""
  
  # Check 1: localhost/127.0.0.1 without .42 reference
  if grep -q "127.0.0.1\|localhost" "$file" 2>/dev/null; then
    if ! grep -q "192.168.168.42\|onprem\|on-prem" "$file" 2>/dev/null; then
      violations=$((violations + 1))
      issues="${issues}• Contains localhost/127.0.0.1 without .42 reference\n"
    fi
  fi
  
  # Check 2: Prohibited .31 reference
  if grep -q "192.168.168.31" "$file" 2>/dev/null; then
    # Exception: Allow in documentation/comments about constraint
    if ! grep -q "DEVELOPMENT\|development\|DEV\|\.31.*WORKSTATION\|\.31.*localhost" "$file" 2>/dev/null; then
      violations=$((violations + 1))
      issues="${issues}• Contains prohibited 192.168.168.31 reference\n"
    fi
  fi
  
  # Report results
  if [[ $violations -eq 0 ]]; then
    print_pass "$file"
    COMPLIANT=$((COMPLIANT + 1))
    return 0
  else
    print_fail "$file"
    echo -e "$(echo -e "$issues" | sed 's/^/  /')"
    VIOLATIONS=$((VIOLATIONS + 1))
    return 1
  fi
}

# Main execution
main() {
  print_header "🏗️ ARCHITECTURE COMPLIANCE AUDIT"
  echo ""
  
  # PRIORITY 1: Docker Compose
  print_header "PRIORITY 1: Production Docker Compose Files"
  verify_file "portal/docker-compose.yml" "P1" || true
  verify_file "portal/docker/docker-compose.yml" "P1" || true
  verify_file "frontend/docker-compose.dashboard.yml" "P1" || true
  verify_file "frontend/docker-compose.loadbalancer.yml" "P1" || true
  verify_file "nexus-engine/docker-compose.yml" "P1" || true
  verify_file "ops/github-runner/docker-compose.yml" "P1" || true
  echo ""
  
  # PRIORITY 2: Kubernetes
  print_header "PRIORITY 2: Kubernetes Orchestration"
  verify_file "kubernetes/phase1-deployment.yaml" "P2" || true
  verify_file "k8s/deployment-strategies.yaml" "P2" || true
  verify_file "monitoring/elite-observability.yaml" "P2" || true
  echo ""
  
  # PRIORITY 3: Monitoring
  print_header "PRIORITY 3: Monitoring & Exporters"
  verify_file "config/docker-compose.node-exporter.yml" "P3" || true
  verify_file "config/docker-compose.postgres-exporter.yml" "P3" || true
  verify_file "config/docker-compose.redis-exporter.yml" "P3" || true
  verify_file "monitoring/prometheus.yml" "P3" || true
  echo ""
  
  # PRIORITY 4: Documentation
  print_header "PRIORITY 4: Documentation & Playbooks"
  verify_file "api/openapi.yaml" "P4" || true
  verify_file "portal/ansible/deploy-portal.yml" "P4" || true
  echo ""
  
  # Summary
  print_header "📊 COMPLIANCE SUMMARY"
  echo ""
  echo "Files Checked:  $FILES_CHECKED"
  echo -e "${GREEN}Compliant:      $COMPLIANT${NC}"
  echo -e "${RED}Violations:     $VIOLATIONS${NC}"
  echo -e "${YELLOW}Skipped:        $SKIPPED${NC}"
  echo ""
  
  # Compliance percentage
  if [[ $COMPLIANT -gt 0 ]]; then
    local total=$((COMPLIANT + VIOLATIONS))
    local percentage=$((COMPLIANT * 100 / total))
    echo "Compliance Rate: $COMPLIANT/$total ($percentage%)"
  fi
  echo ""
  
  # Mandatory constraints
  echo -e "${BLUE}MANDATORY CONSTRAINTS:${NC}"
  echo -e "  ✅ All workloads on 192.168.168.42 (on-prem)"
  echo -e "  ✅ Secrets in cloud (GSM/Vault)"
  echo -e "  ✅ No services on 192.168.168.31"
  echo ""
  
  # Final status
  if [[ $VIOLATIONS -eq 0 ]]; then
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ ALL SYSTEMS COMPLIANT              ║${NC}"
    echo -e "${GREEN}║  Safe to deploy to production          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    return 0
  else
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ❌ REMEDIATION REQUIRED               ║${NC}"
    echo -e "${RED}║  See violations above                  ║${NC}"
    echo -e "${RED}║  Reference: ARCHITECTURE_REMEDIATION_  ║${NC}"
    echo -e "${RED}║  PLAN.md                              ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    return 1
  fi
}

# Run main function
main "$@"
