#!/bin/bash
#
# idempotent GCP Workload Identity Federation Setup
# Configures GCP WIF for GitHub Actions OIDC authentication
#

set -euo pipefail

PROJECT_ID="${1:-}"
LOG_DIR="${2:-.setup-logs}"
DRY_RUN="${3:-false}"

if [[ -z "$PROJECT_ID" ]]; then
    echo "Error: PROJECT_ID required"
    exit 1
fi

mkdir -p "$LOG_DIR"
SETUP_LOG="${LOG_DIR}/gcp-wif-setup-$(date +%s).log"

{
    echo "=== GCP Workload Identity Federation Setup ==="
    echo "Project ID: $PROJECT_ID"
    echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Dry Run: $DRY_RUN"
    echo ""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Function: Setup WIF Pool (idempotent)
    setup_wif_pool() {
        local project="$1"
        local pool_id="github-actions-pool"
        local pool_display_name="GitHub Actions"
        
        echo "Checking WIF pool: $pool_id..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would create WIF pool: $pool_id"
            return
        fi
        
        # Check if pool exists
        EXISTING=$(gcloud iam workload-identity-pools list \
            --location=global \
            --project="$project" \
            --format="value(name)" \
            --filter="displayName=$pool_display_name" 2>/dev/null || echo "")
        
        if [[ -n "$EXISTING" ]]; then
            echo "WIF pool already exists: $EXISTING"
            POOL_NAME="$EXISTING"
        else
            echo "Creating WIF pool..."
            gcloud iam workload-identity-pools create "$pool_id" \
                --location=global \
                --display-name="$pool_display_name" \
                --project="$project"
            
            POOL_NAME="projects/${project}/locations/global/workloadIdentityPools/${pool_id}"
            echo "Created WIF pool: $POOL_NAME"
        fi
        
        echo "$POOL_NAME"
    }
    
    # Function: Setup WIF Provider (idempotent)
    setup_wif_provider() {
        local pool_name="$1"
        local provider_id="github-provider"
        
        echo "Checking WIF provider: $provider_id..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would create WIF provider: $provider_id"
            return
        fi
        
        # Check if provider exists
        EXISTING=$(gcloud iam workload-identity-pools providers list \
            --location=global \
            --workload-identity-pool="$pool_name" \
            --format="value(name)" 2>/dev/null | grep "$provider_id" || echo "")
        
        if [[ -n "$EXISTING" ]]; then
            echo "WIF provider already exists: $EXISTING"
            PROVIDER_NAME="$EXISTING"
        else
            echo "Creating WIF provider..."
            gcloud iam workload-identity-pools providers create-oidc "$provider_id" \
                --location=global \
                --workload-identity-pool="$pool_name" \
                --display-name="GitHub" \
                --attribute-mapping="google.subject=assertion.sub,attribute.aud=assertion.aud" \
                --issuer-uri="https://token.actions.githubusercontent.com"
            
            PROVIDER_NAME="$pool_name/providers/$provider_id"
            echo "Created WIF provider: $PROVIDER_NAME"
        fi
        
        echo "$PROVIDER_NAME"
    }
    
    # Function: Create Service Account (idempotent)
    create_service_account() {
        local project="$1"
        local sa_id="github-actions-sa"
        
        echo "Checking service account: $sa_id..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would create service account: $sa_id"
            return
        fi
        
        # Check if SA exists
        EXISTING=$(gcloud iam service-accounts list \
            --project="$project" \
            --format="value(email)" \
            --filter="displayName=$sa_id" 2>/dev/null || echo "")
        
        if [[ -n "$EXISTING" ]]; then
            echo "Service account already exists: $EXISTING"
            SA_EMAIL="$EXISTING"
        else
            echo "Creating service account..."
            gcloud iam service-accounts create "$sa_id" \
                --display-name="GitHub Actions Service Account" \
                --project="$project"
            
            SA_EMAIL="${sa_id}@${project}.iam.gserviceaccount.com"
            echo "Created service account: $SA_EMAIL"
        fi
        
        echo "$SA_EMAIL"
    }
    
    # Function: Grant roles to service account (idempotent)
    grant_sa_roles() {
        local project="$1"
        local sa_email="$2"
        
        echo "Granting roles to service account..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would grant roles to: $sa_email"
            return
        fi
        
        # Roles to grant
        local roles=(
            "roles/secretmanager.secretAccessor"
            "roles/container.developer"
        )
        
        for role in "${roles[@]}"; do
            echo "  - Granting $role..."
            gcloud projects add-iam-policy-binding "$project" \
                --member="serviceAccount:${sa_email}" \
                --role="$role" \
                --quiet 2>/dev/null || echo "    (may already exist)"
        done
    }
    
    # Function: Bind WIF provider to service account (idempotent)
    bind_wif_to_sa() {
        local provider_name="$1"
        local sa_email="$2"
        
        echo "Binding WIF to service account..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY-RUN] Would bind WIF provider to: $sa_email"
            return
        fi
        
        # Extract project and pool from provider name
        local project=$(echo "$provider_name" | cut -d'/' -f2)
        
        # Configure attribute mapping and binding
        gcloud iam service-accounts add-iam-policy-binding "$sa_email" \
            --role="roles/iam.workloadIdentityUser" \
            --principal="principalSet://iam.googleapis.com/projects/${project}/locations/global/workloadIdentityPools/*/providers/*" \
            --quiet 2>/dev/null || true
        
        echo "WIF binding complete"
    }
    
    # Main orchestration
    POOL_NAME=$(setup_wif_pool "$PROJECT_ID")
    PROVIDER_NAME=$(setup_wif_provider "$POOL_NAME")
    SA_EMAIL=$(create_service_account "$PROJECT_ID")
    grant_sa_roles "$PROJECT_ID" "$SA_EMAIL"
    bind_wif_to_sa "$PROVIDER_NAME" "$SA_EMAIL"
    
    # Output configuration
    echo ""
    echo "=== GCP WIF Setup Complete ==="
    echo "Workload Identity Provider: $PROVIDER_NAME"
    echo "Service Account: $SA_EMAIL"
    echo ""
    echo "Use these in GitHub Secrets:"
    echo "  GCP_WORKLOAD_IDENTITY_PROVIDER=$PROVIDER_NAME"
    echo "  GCP_SERVICE_ACCOUNT=$SA_EMAIL"
    echo "  GCP_PROJECT_ID=$PROJECT_ID"
    
    # Save output
    echo "$PROVIDER_NAME" > "${LOG_DIR}/gcp-provider.txt"
    echo "$SA_EMAIL" > "${LOG_DIR}/gcp-sa-email.txt"
    echo "$PROJECT_ID" > "${LOG_DIR}/gcp-project-id.txt"

} | tee "$SETUP_LOG"

echo "Setup log saved to: $SETUP_LOG"
