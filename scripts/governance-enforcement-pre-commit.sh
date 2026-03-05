#!/bin/bash
# ============================================================================
# INFRASTRUCTURE GOVERNANCE ENFORCEMENT - Pre-Commit Hook
# ============================================================================
# Purpose: Validate commits against infrastructure governance policies
# Deployment: .git/hooks/pre-commit & .husky/pre-commit
# Failure: Blocks commit with compliance violation
# ============================================================================

set -e

CONTROL_PLANE_IP="192.168.168.31"
WORKER_NODE_IP="192.168.168.42"
MIN_NODE_VERSION="20.19.0"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Infrastructure Governance Pre-Commit Hook ===${NC}"

VIOLATIONS=0

# ============================================================================
# CHECK 1: Node Version Requirement
# ============================================================================
echo -e "\n${YELLOW}[1/6] Checking Node.js version...${NC}"
CURRENT_NODE=$(node --version 2>/dev/null | sed 's/v//' || echo "NOT_INSTALLED")

if [ "$CURRENT_NODE" = "NOT_INSTALLED" ]; then
  echo -e "${RED}✗ FAIL${NC}: Node.js not installed. Required >= $MIN_NODE_VERSION"
  VIOLATIONS=$((VIOLATIONS + 1))
else
  if [[ "$CURRENT_NODE" > "$MIN_NODE_VERSION" ]] || [[ "$CURRENT_NODE" = "$MIN_NODE_VERSION" ]]; then
    echo -e "${GREEN}✓ PASS${NC}: Node.js $CURRENT_NODE (>= $MIN_NODE_VERSION)"
  else
    echo -e "${RED}✗ FAIL${NC}: Node.js $CURRENT_NODE (< $MIN_NODE_VERSION required)"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
fi

# ============================================================================
# CHECK 2: Docker Compose - No external localhost binding (healthchecks OK)
# ============================================================================
echo -e "\n${YELLOW}[2/6] Checking docker-compose files for external localhost binding...${NC}"
LOCALHOST_FILES=$(find . -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null | grep -v node_modules | grep -v '.git') 

if [ -z "$LOCALHOST_FILES" ]; then
  echo -e "${GREEN}✓ PASS${NC}: No docker-compose files found"
else
  # Exclude healthcheck tests (internal container checks are OK)
  LOCALHOST_EXTERNAL=$(echo "$LOCALHOST_FILES" | xargs grep -v "healthcheck\|test:" 2>/dev/null | grep -l "localhost\|127.0.0.1" || true)
  if [ -z "$LOCALHOST_EXTERNAL" ]; then
    echo -e "${GREEN}✓ PASS${NC}: No external localhost bindings in docker-compose files"
  else
    echo -e "${RED}✗ FAIL${NC}: Found external localhost bindings in:"
    echo "$LOCALHOST_EXTERNAL" | sed 's/^/  /'
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
fi

# ============================================================================
# CHECK 3: Production Config Files - No hardcoded 192.168.168.31
# ============================================================================
echo -e "\n${YELLOW}[3/6] Checking for hardcoded control plane references in production configs...${NC}"
CONTROL_PLANE_REFS=$(find . -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.tf" -o -name ".env*" \) \
  \( -path "*/deploy/*" -o -path "*/config/*" \) \
  ! -name "infrastructure-env.sh" \
  2>/dev/null | \
  xargs grep -l "$CONTROL_PLANE_IP" 2>/dev/null || true)

if [ -z "$CONTROL_PLANE_REFS" ]; then
  echo -e "${GREEN}✓ PASS${NC}: No hardcoded control plane references in production configs"
else
  echo -e "${RED}✗ FAIL${NC}: Found control plane ($CONTROL_PLANE_IP) references in:"
  echo "$CONTROL_PLANE_REFS" | sed 's/^/  /'
  VIOLATIONS=$((VIOLATIONS + 1))
fi

# ============================================================================
# CHECK 4: Worker Node Config - References 192.168.168.42
# ============================================================================
echo -e "\n${YELLOW}[4/6] Validating worker node endpoint configuration...${NC}"
WORKER_CONFIG_FILES=$(find . -type f \( -name "vite.config.ts" -o -name "vite.config.js" \) 2>/dev/null | grep -v node_modules | grep -v '.git')

if [ -z "$WORKER_CONFIG_FILES" ]; then
  echo -e "${YELLOW}⚠ INFO${NC}: No Vite config files found"
else
  WORKER_REFS=$(echo "$WORKER_CONFIG_FILES" | xargs grep -l "$WORKER_NODE_IP" 2>/dev/null || true)
  if [ -n "$WORKER_REFS" ]; then
    echo -e "${GREEN}✓ PASS${NC}: Found valid worker node references"
  else
    echo -e "${YELLOW}⚠ WARN${NC}: Consider documenting worker node in comments"
  fi
fi

# ============================================================================
# CHECK 5: Vite Config - Host bound to 0.0.0.0, not localhost
# ============================================================================
echo -e "\n${YELLOW}[5/6] Checking Vite config for correct host binding...${NC}"
VITE_FILES=$(find . -name "vite.config.ts" -o -name "vite.config.js" 2>/dev/null | grep -v node_modules)

if [ -z "$VITE_FILES" ]; then
  echo -e "${GREEN}✓ PASS${NC}: No Vite files to check"
else
  LOCALHOST_VITE=$(echo "$VITE_FILES" | xargs grep -l "host.*localhost\|host.*127.0.0.1" 2>/dev/null || true)
  if [ -z "$LOCALHOST_VITE" ]; then
    echo -e "${GREEN}✓ PASS${NC}: Vite host correctly configured"
  else
    echo -e "${RED}✗ FAIL${NC}: Vite binding to localhost in:"
    echo "$LOCALHOST_VITE" | sed 's/^/  /'
    echo "  → Change 'host: localhost' to 'host: 0.0.0.0'"
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
fi

# ============================================================================
# CHECK 6: Node.js Service Scripts - No localhost hardcoding
# ============================================================================
echo -e "\n${YELLOW}[6/6] Checking Node.js service files...${NC}"
SERVICE_FILES=$(find ./services -name "*.js" -o -name "*.ts" 2>/dev/null | head -20)

if [ -z "$SERVICE_FILES" ]; then
  echo -e "${GREEN}✓ PASS${NC}: No service files to validate"
else
  LOCALHOST_SERVICES=$(echo "$SERVICE_FILES" | xargs grep -l "listen.*localhost\|127.0.0.1" 2>/dev/null || true)
  if [ -z "$LOCALHOST_SERVICES" ]; then
    echo -e "${GREEN}✓ PASS${NC}: Service files correctly configured"
  else
    echo -e "${RED}✗ FAIL${NC}: Found localhost hardcoding in services:"
    echo "$LOCALHOST_SERVICES" | sed 's/^/  /'
    VIOLATIONS=$((VIOLATIONS + 1))
  fi
fi

# ============================================================================
# RESULT
# ============================================================================
echo -e "\n${YELLOW}=== Governance Check Summary ===${NC}"
if [ $VIOLATIONS -eq 0 ]; then
  echo -e "${GREEN}✓ All governance checks passed!${NC}"
  echo "Commit is compliant with infrastructure governance policy."
  exit 0
else
  echo -e "${RED}✗ FAILED: $VIOLATIONS governance violations detected${NC}"
  echo ""
  echo "Please fix violations before committing:"
  echo "  1. Update Node.js to >= $MIN_NODE_VERSION"
  echo "  2. Remove localhost/127.0.0.1 bindings from configs"
  echo "  3. Ensure services target $WORKER_NODE_IP"
  echo "  4. Bind services to 0.0.0.0, not localhost"
  echo ""
  echo "See INFRASTRUCTURE_GOVERNANCE.md for details."
  exit 1
fi
