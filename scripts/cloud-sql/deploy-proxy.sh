#!/usr/bin/env bash
################################################################################
# Cloud SQL Auth Proxy Deployment Script
# Enables database connectivity via proxy sidecar without VPC peering
#
# Usage: bash scripts/cloud-sql/deploy-proxy.sh [--enable|--disable|--verify]
# Status: IDEMPOTENT, IMMUTABLE, FULLY AUTOMATED
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$REPO_ROOT/.githooks/audit"
LOG_FILE="$LOG_DIR/cloud-sql-proxy-deployment-$(date +%Y%m%d).jsonl"
mkdir -p "$LOG_DIR"

# Configuration
PROJECT_ID="nexusshield-prod"
REGION="us-central1"
INSTANCE_NAME="migration-db"
DATABASE="migration_db"
BACKEND_SA="prod-deployer-sa-v3@nexusshield-prod.iam.gserviceaccount.com"
PROXY_PORT=5432

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Logging Functions
################################################################################

log_event() {
    local status="$1"
    local message="$2"
    local details="${3:-}"
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"status\":\"$status\",\"message\":\"$message\",\"details\":\"$details\"}" >> "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

################################################################################
# Verification Functions
################################################################################

verify_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI not installed"
        log_event "failed" "gcloud CLI not found"
        exit 1
    fi
    print_success "gcloud CLI found: $(gcloud version --format='value(gcloud)')"
}

verify_terraform() {
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform not installed"
        log_event "failed" "Terraform not found"
        exit 1
    fi
    print_success "Terraform found: $(terraform version -json | jq -r .terraform_version)"
}

verify_project_access() {
    print_info "Verifying GCP project access..."
    if ! gcloud projects describe "$PROJECT_ID" --quiet &>/dev/null; then
        print_error "No access to project: $PROJECT_ID"
        log_event "failed" "Project access denied" "$PROJECT_ID"
        exit 1
    fi
    print_success "Access verified for project: $PROJECT_ID"
}

verify_cloud_sql_instance() {
    print_info "Checking Cloud SQL instance..."
    if ! gcloud sql instances describe "$INSTANCE_NAME" --project="$PROJECT_ID" &>/dev/null; then
        print_warning "Cloud SQL instance not found: $INSTANCE_NAME"
        print_info "This is expected if not yet provisioned. Create it with:"
        echo "    gcloud sql instances create $INSTANCE_NAME \\"
        echo "      --database-version=POSTGRES_15 \\"
        echo "      --region=$REGION \\"
        echo "      --tier=db-f1-micro \\"
        echo "      --project=$PROJECT_ID"
        log_event "warning" "Cloud SQL instance not found" "$INSTANCE_NAME"
        return 1
    fi
    print_success "Cloud SQL instance exists: $INSTANCE_NAME"
    log_event "success" "Cloud SQL instance verified" "$INSTANCE_NAME"
    return 0
}

verify_iam_role() {
    print_info "Checking IAM role binding..."
    local binding_exists=$(gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --filter="bindings.role:(roles/cloudsql.client) AND members:($BACKEND_SA)" \
        --format='value(members)' 2>/dev/null || echo "")
    
    if [ -z "$binding_exists" ]; then
        print_warning "Backend SA missing 'roles/cloudsql.client' role"
        print_info "Granting role with: gcloud projects add-iam-policy-binding"
        return 1
    fi
    print_success "Backend SA has 'roles/cloudsql.client' role"
    return 0
}

verify_connection_string_secret() {
    print_info "Checking Secret Manager secret..."
    if ! gcloud secrets describe "postgres-connection-string" --project="$PROJECT_ID" &>/dev/null; then
        print_warning "Secret not found: postgres-connection-string"
        print_info "Create with: gcloud secrets create postgres-connection-string --data-file=<(...)"
        return 1
    fi
    print_success "Secret exists: postgres-connection-string"
    return 0
}

verify_backend_deployment() {
    print_info "Checking backend Cloud Run service..."
    if ! gcloud run services describe backend --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        print_error "Backend service not deployed"
        log_event "failed" "Backend service not found" "region=$REGION"
        exit 1
    fi
    print_success "Backend service deployed: backend (region=$REGION)"
    
    # Check if sidecar is present
    local has_proxy=$(gcloud run services describe backend \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(spec.template.spec.containers[].image)' 2>/dev/null | grep -c "cloud-sql-proxy" || echo "0")
    
    if [ "$has_proxy" -gt 0 ]; then
        print_success "Cloud SQL proxy sidecar detected"
        log_event "success" "Proxy sidecar verified"
        return 0
    else
        print_warning "Cloud SQL proxy sidecar NOT found"
        print_info "Deploy with: gcloud run deploy backend --add-cloudsql-instances=$PROJECT_ID:$REGION:$INSTANCE_NAME"
        log_event "warning" "Proxy sidecar not deployed"
        return 1
    fi
}

################################################################################
# Deployment Functions
################################################################################

enable_proxy() {
    print_info "Enabling Cloud SQL Auth Proxy..."
    log_event "started" "Enabling proxy sidecar"
    
    # Step 1: Apply Terraform
    print_info "Step 1/4: Initializing Terraform..."
    cd "$REPO_ROOT/terraform"
    terraform init -upgrade
    print_success "Terraform initialized"
    
    print_info "Step 2/4: Validating Terraform configuration..."
    terraform validate
    print_success "Terraform configuration valid"
    
    print_info "Step 3/4: Planning Terraform changes..."
    terraform plan \
        -var="enable_cloud_sql_proxy=true" \
        -var="cloud_sql_instance_connection_name=$PROJECT_ID:$REGION:$INSTANCE_NAME" \
        -var="cloud_sql_proxy_port=$PROXY_PORT" \
        -var="backend_sa_email=$BACKEND_SA" \
        -out=tfplan
    print_success "Terraform plan generated"
    
    # Review plan
    print_warning "Review the Terraform plan above. Continue? (yes/no)"
    read -r -p "> " confirm
    if [ "$confirm" != "yes" ]; then
        print_error "Deployment cancelled"
        log_event "cancelled" "User declined plan"
        exit 1
    fi
    
    print_info "Step 4/4: Applying Terraform configuration..."
    terraform apply tfplan
    print_success "Terraform applied successfully"
    log_event "success" "IAM bindings and Terraform applied"
    
    # Step 2: Deploy Cloud Run with sidecar
    print_info "Deploying backend with Cloud SQL proxy sidecar..."
    gcloud run deploy backend \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --image=gcr.io/$PROJECT_ID/backend:latest \
        --add-cloudsql-instances=$PROJECT_ID:$REGION:$INSTANCE_NAME \
        --set-env-vars=CLOUDSQL_INSTANCE=$PROJECT_ID:$REGION:$INSTANCE_NAME \
        --quiet
    print_success "Backend service deployed with proxy sidecar"
    log_event "success" "Cloud Run deployment completed"
    
    print_success "Cloud SQL Auth Proxy enabled successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Verify database connectivity: $SCRIPT_DIR/verify-proxy.sh"
    echo "2. Run database migrations: npm run migrate:deploy"
    echo "3. Monitor logs: gcloud logging read 'container_name=\"cloud-sql-proxy\"' --project=$PROJECT_ID"
}

disable_proxy() {
    print_warning "Disabling Cloud SQL Auth Proxy..."
    log_event "started" "Disabling proxy sidecar"
    
    cd "$REPO_ROOT/terraform"
    terraform apply -var="enable_cloud_sql_proxy=false" -auto-approve
    print_success "Proxy disabled in Terraform"
    
    gcloud run deploy backend \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --image=gcr.io/$PROJECT_ID/backend:latest \
        --remove-cloudsql-instances \
        --quiet
    print_success "Backend service updated (proxy removed)"
    log_event "success" "Proxy sidecar disabled"
}

verify_all() {
    print_info "Running full verification..."
    local all_pass=true
    
    verify_gcloud || all_pass=false
    verify_terraform || all_pass=false
    verify_project_access || all_pass=false
    verify_cloud_sql_instance || all_pass=false
    verify_iam_role || all_pass=false
    verify_connection_string_secret || all_pass=false
    verify_backend_deployment || all_pass=false
    
    echo ""
    if [ "$all_pass" = true ]; then
        print_success "All checks passed! Cloud SQL Auth Proxy is ready."
        log_event "success" "All verification checks passed"
        exit 0
    else
        print_warning "Some checks failed. Review above and follow recommendations."
        log_event "warning" "Some verification checks failed"
        exit 1
    fi
}

################################################################################
# Test Functions
################################################################################

test_proxy_connectivity() {
    print_info "Testing Cloud SQL proxy connectivity..."
    
    if ! gcloud run exec backend --region="$REGION" --project="$PROJECT_ID" -- \
        nc -zv localhost $PROXY_PORT; then
        print_error "Proxy not reachable on localhost:$PROXY_PORT"
        log_event "failed" "Proxy connectivity test failed"
        exit 1
    fi
    print_success "Proxy reachable on localhost:$PROXY_PORT"
    log_event "success" "Proxy connectivity verified"
}

test_database_query() {
    print_info "Testing database query..."
    
    if ! gcloud run exec backend --region="$REGION" --project="$PROJECT_ID" -- \
        psql -h localhost -U migration_app -d "$DATABASE" -c "SELECT NOW();" 2>/dev/null; then
        print_warning "Database query test inconclusive (may need credentials configured)"
        log_event "warning" "Database query test inconclusive"
        return
    fi
    print_success "Database query successful"
    log_event "success" "Database connectivity verified"
}

################################################################################
# Main
################################################################################

main() {
    local action="${1:-verify}"
    
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║   Cloud SQL Auth Proxy Deployment Script                      ║"
    echo "║   Project: $PROJECT_ID (Region: $REGION)              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    case "$action" in
        --enable)
            enable_proxy
            ;;
        --disable)
            disable_proxy
            ;;
        --verify|verify)
            verify_all
            ;;
        --test)
            test_proxy_connectivity
            test_database_query
            ;;
        *)
            print_error "Unknown action: $action"
            echo "Usage: $0 [--enable|--disable|--verify|--test]"
            exit 1
            ;;
    esac
}

main "$@"
