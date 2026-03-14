#!/bin/bash
###############################################################################
# SSO/OAuth Platform - Unified Deployment Orchestrator
# Production-ready deployment with all components
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SSO_DIR="${PROJECT_ROOT}/infrastructure/sso"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_header() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BLUE}$1${NC}\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
log_step() { echo -e "${YELLOW}→${NC} $1"; }
log_success() { echo -e "${GREEN}✅${NC} $1"; }
log_error() { echo -e "${RED}❌${NC} $1" >&2; }

# Check prerequisites
check_prerequisites() {
  log_header "Checking Prerequisites"
  
  command -v kubectl &>/dev/null || { log_error "kubectl not found"; exit 1; }
  log_success "kubectl installed"
  
  command -v jq &>/dev/null || { log_error "jq not found"; exit 1; }
  log_success "jq installed"
  
  kubectl cluster-info &>/dev/null || { log_error "Kubernetes cluster not accessible"; exit 1; }
  log_success "Kubernetes cluster accessible"
}

# Gather credentials
gather_credentials() {
  log_header "Gathering Credentials"
  
  read -p "$(echo -e ${YELLOW}→${NC}) Keycloak database password: " -s KC_DB_PASS
  echo ""
  [[ -z "$KC_DB_PASS" ]] && { log_error "Database password required"; exit 1; }
  
  read -p "$(echo -e ${YELLOW}→${NC}) Keycloak admin password: " -s KC_ADMIN_PASS  
  echo ""
  [[ -z "$KC_ADMIN_PASS" ]] && { log_error "Admin password required"; exit 1; }
  
  read -p "$(echo -e ${YELLOW}→${NC}) Google OAuth Client ID: " GOOGLE_CLIENT_ID
  [[ -z "$GOOGLE_CLIENT_ID" ]] && { log_error "Google Client ID required"; exit 1; }
  
  read -p "$(echo -e ${YELLOW}→${NC}) Google OAuth Client Secret: " -s GOOGLE_CLIENT_SECRET
  echo ""
  [[ -z "$GOOGLE_CLIENT_SECRET" ]] && { log_error "Google Client Secret required"; exit 1; }
  
  read -p "$(echo -e ${YELLOW}→${NC}) OAuth2-Proxy client secret: " -s OAUTH2_PROXY_SECRET
  echo ""
  [[ -z "$OAUTH2_PROXY_SECRET" ]] && { log_error "OAuth2-Proxy secret required"; exit 1; }
  
  read -p "$(echo -e ${YELLOW}→${NC}) OAuth2-Proxy cookie secret: " -s COOKIE_SECRET
  echo ""
  [[ -z "$COOKIE_SECRET" ]] && { log_error "Cookie secret required"; exit 1; }
  
  log_success "All credentials gathered"
}

# Deploy infrastructure
deploy_infrastructure() {
  log_header "Deploying SSO Infrastructure (7 Phases)"
  
  # Phase 1: Namespaces
  log_step "Phase 1: Creating namespaces..."
  kubectl apply -f "$SSO_DIR/1-keycloak-namespace.yaml" 2>/dev/null
  sleep 3
  log_success "Namespaces created"
  
  # Phase 2: Update secrets with provided credentials
  log_step "Phase 2: Creating secrets with provided credentials..."
  kubectl patch secret keycloak-db-password -n keycloak -p "{\"data\":{\"password\":\"$(echo -n "$KC_DB_PASS" | base64)\"}}" 2>/dev/null || true
  kubectl patch secret keycloak-admin -n keycloak -p "{\"data\":{\"password\":\"$(echo -n "$KC_ADMIN_PASS" | base64)\"}}" 2>/dev/null || true
  kubectl create secret generic keycloak-google-oauth -n keycloak --from-literal="client_id=$GOOGLE_CLIENT_ID" --from-literal="client_secret=$GOOGLE_CLIENT_SECRET" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
  kubectl create secret generic oauth2-proxy-secrets -n oauth2-proxy --from-literal="client_secret=$OAUTH2_PROXY_SECRET" --from-literal="cookie_secret=$COOKIE_SECRET" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
  log_success "Secrets created"
  
  # Phase 3: PostgreSQL
  log_step "Phase 3: Deploying PostgreSQL..."
  kubectl apply -f "$SSO_DIR/2-keycloak-postgres.yaml" 2>/dev/null
  log_success "PostgreSQL deployed (waiting for startup...)"
  
  # Wait for PostgreSQL to be ready
  echo -n "  Waiting for PostgreSQL..."
  for i in {1..120}; do
    if kubectl get statefulset keycloak-postgres -n keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q "1"; then
      echo " ✓"
      break
    fi
    echo -n "."
    sleep 2
  done
  
  # Phase 4: Keycloak realm config
  log_step "Phase 4: Creating Keycloak realm configuration..."
  kubectl apply -f "$SSO_DIR/3-keycloak-realm-config.yaml" 2>/dev/null
  log_success "Realm config ready"
  
  # Phase 5: Keycloak deployment
  log_step "Phase 5: Deploying Keycloak (3-node HA)..."
  kubectl apply -f "$SSO_DIR/4-keycloak-deployment.yaml" 2>/dev/null
  log_success "Keycloak deployed"
  
  # Wait for Keycloak
  echo -n "  Waiting for Keycloak..."
  for i in {1..120}; do
    if [ $(kubectl get deployment keycloak -n keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null) -ge 2 ]; then
      echo " ✓"
      break
    fi
    echo -n "."
    sleep 3
  done
  
  # Phase 6: OAuth2-Proxy
  log_step "Phase 6: Deploying OAuth2-Proxy (3-node HA)..."
  kubectl apply -f "$SSO_DIR/6-oauth2-proxy-config.yaml" 2>/dev/null
  log_success "OAuth2-Proxy deployed"
  
  # Phase 7: Ingress & Monitoring
  log_step "Phase 7: Configuring Ingress and monitoring..."
  kubectl apply -f "$SSO_DIR/8-oauth2-proxy-ingress.yaml" 2>/dev/null
  kubectl apply -f "$SSO_DIR/monitoring/oauth2-proxy-servicemonitor.yaml" 2>/dev/null
  log_success "Ingress and monitoring configured"
  
  log_success "SSO Infrastructure deployment complete!"
}

# Verify deployment
verify_deployment() {
  log_header "Verifying Deployment"
  
  echo -e "\n${BLUE}Keycloak namespace:${NC}"
  kubectl get pods -n keycloak || true
  
  echo -e "\n${BLUE}OAuth2-Proxy namespace:${NC}"
  kubectl get pods -n oauth2-proxy || true
  
  echo -e "\n${BLUE}Services:${NC}"
  kubectl get svc -n keycloak -n oauth2-proxy || true
  
  log_success "Deployment verification complete"
}

# Print next steps
print_next_steps() {
  log_header "Next Steps"
  
  cat << 'EOF'

🎯 Deployment Complete! Your SSO platform is now running.

👥 MANUAL TESTING (Run in browser):
  1. Visit: https://portal.nexus.local/api/v1/products
  2. Should redirect to: https://keycloak.nexus.local/realms/nexusshield-prod/protocol/openid-connect/auth
  3. Click "Sign in with Google"
  4. Authenticate with Google account
  5. Should redirect back to endpoint with auth headers

📊 MONITOR DEPLOYMENT:
  kubectl get pods -n keycloak -n oauth2-proxy -w
  
📝 VIEW LOGS:
  kubectl logs -n keycloak -l app=keycloak -f
  kubectl logs -n oauth2-proxy -l app=oauth2-proxy -f
  
🔧 KEYCLOAK ADMIN CONSOLE:
  https://keycloak.nexus.local/admin
  Username: admin
  (Password stored in: kubectl get secret keycloak-admin -n keycloak)
  
🚀 ADD FUTURE PROVIDERS:
  bash infrastructure/scripts/sso/add-microsoft-provider.sh
  bash infrastructure/scripts/sso/add-aws-provider.sh
  bash infrastructure/scripts/sso/add-github-provider.sh
  bash infrastructure/scripts/sso/add-gitlab-provider.sh
  bash infrastructure/scripts/sso/add-x-provider.sh

EOF
}

# Main execution
main() {
  check_prerequisites
  gather_credentials
  deploy_infrastructure
  verify_deployment
  print_next_steps
}

main "$@"
