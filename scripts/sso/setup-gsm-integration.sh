#!/bin/bash
set -e

# GSM/KMS Setup Script for SSO Platform
# Creates Google Secret Manager secrets and KMS keys for credential management
# Implements workload identity for Kubernetes access

PROJECT_ID="${1:-nexus-prod}"
REGION="${2:-us-central1}"
GKE_CLUSTER="${3:-nexus-prod-gke}"
GKE_ZONE="${4:-us-central1-a}"

echo "🔐 Setting up Google Secret Manager and Cloud KMS for SSO Platform"
echo "   Project: $PROJECT_ID"
echo "   Region: $REGION"
echo "   Cluster: $GKE_CLUSTER (Zone: $GKE_ZONE)"
echo ""

# Verify gcloud is authenticated
gcloud auth list --filter=status:ACTIVE --format="value(account)" > /dev/null 2>&1 || {
  echo "❌ gcloud is not authenticated. Run: gcloud auth login"
  exit 1
}

# Create KMS keyring
echo "📁 Creating KMS keyring..."
if gcloud kms keyrings describe sso-keyring \
  --location "$REGION" \
  --project "$PROJECT_ID" >/dev/null 2>&1; then
  echo "   ✅ KMS keyring already exists"
else
  gcloud kms keyrings create sso-keyring \
    --location "$REGION" \
    --project "$PROJECT_ID"
  echo "   ✅ KMS keyring created"
fi

# Create KMS encryption key
echo "🔑 Creating KMS encryption key..."
if gcloud kms keys describe sso-key \
  --location "$REGION" \
  --keyring sso-keyring \
  --project "$PROJECT_ID" >/dev/null 2>&1; then
  echo "   ✅ KMS key already exists"
else
  gcloud kms keys create sso-key \
    --location "$REGION" \
    --keyring sso-keyring \
    --purpose encryption \
    --project "$PROJECT_ID"
  echo "   ✅ KMS key created"
fi

# Function to create or update secret
create_or_update_secret() {
  local secret_name="$1"
  local secret_value="$2"
  
  if gcloud secrets describe "$secret_name" --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "   ✅ Secret '$secret_name' already exists, adding version"
    echo -n "$secret_value" | gcloud secrets versions add "$secret_name" \
      --data-file=- \
      --project "$PROJECT_ID"
  else
    echo "   Creating secret '$secret_name'"
    echo -n "$secret_value" | gcloud secrets create "$secret_name" \
      --replication-policy="automatic" \
      --data-file=- \
      --project "$PROJECT_ID"
    echo "   ✅ Secret '$secret_name' created"
  fi
}

# Create secrets for database credentials
echo "🔐 Creating database credentials secrets..."
create_or_update_secret "keycloak-db-username" "keycloak"
create_or_update_secret "keycloak-db-password" "$(openssl rand -base64 32)"

# Create secrets for Keycloak admin
echo "🔐 Creating Keycloak admin credentials secrets..."
create_or_update_secret "keycloak-admin-username" "admin"
create_or_update_secret "keycloak-admin-password" "$(openssl rand -base64 32)"

# Create Google OAuth credentials (user needs to set these manually)
echo "🔐 Creating Google OAuth credentials placeholder..."
create_or_update_secret "google-oauth-client-id" "REPLACE_WITH_YOUR_GOOGLE_CLIENT_ID"
create_or_update_secret "google-oauth-client-secret" "REPLACE_WITH_YOUR_GOOGLE_CLIENT_SECRET"

# Create service accounts for workload identity
echo "👤 Setting up GCP service accounts for Workload Identity..."

create_or_update_gcp_sa() {
  local sa_name="$1"
  local sa_display="$2"
  
  if gcloud iam service-accounts describe "$sa_name@$PROJECT_ID.iam.gserviceaccount.com" \
    --project "$PROJECT_ID" >/dev/null 2>&1; then
    echo "   ✅ Service account '$sa_name' already exists"
  else
    gcloud iam service-accounts create "$sa_name" \
      --display-name="$sa_display" \
      --project "$PROJECT_ID"
    echo "   ✅ Service account '$sa_name' created"
  fi
}

create_or_update_gcp_sa "sso-keycloak" "SSO Keycloak Service Account"
create_or_update_gcp_sa "sso-oauth2-proxy" "SSO OAuth2-Proxy Service Account"
create_or_update_gcp_sa "sso-postgres" "SSO PostgreSQL Service Account"

# Grant Secret Manager access
echo "🔑 Granting Secret Manager permissions..."
for sa in sso-keycloak sso-oauth2-proxy sso-postgres; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet
  echo "   ✅ Granted secretmanager.secretAccessor to $sa"
done

# Grant KMS permissions
echo "🔑 Granting KMS permissions..."
for sa in sso-keycloak sso-oauth2-proxy sso-postgres; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
    --quiet
  echo "   ✅ Granted cloudkms.cryptoKeyEncrypterDecrypter to $sa"
done

# Grant Cloud Storage access for backups
echo "🔑 Granting Cloud Storage permissions..."
for sa in sso-keycloak sso-postgres; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/storage.objectAdmin" \
    --quiet
  echo "   ✅ Granted storage.objectAdmin to $sa"
done

# Bind Kubernetes service accounts to GCP service accounts
echo "🔗 Binding Kubernetes service accounts to GCP service accounts..."

bind_k8s_to_gcp_sa() {
  local k8s_sa="$1"
  local k8s_ns="$2"
  local gcp_sa="$3"
  
  gcloud iam service-accounts add-iam-policy-binding "$gcp_sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:$PROJECT_ID.svc.id.goog[$k8s_ns/$k8s_sa]" \
    --project "$PROJECT_ID" \
    --quiet
  echo "   ✅ Bound K8s SA $k8s_ns/$k8s_sa to GCP SA $gcp_sa"
}

bind_k8s_to_gcp_sa "gke-workload-identity-keycloak" "keycloak" "sso-keycloak"
bind_k8s_to_gcp_sa "gke-workload-identity-oauth2-proxy" "oauth2-proxy" "sso-oauth2-proxy"
bind_k8s_to_gcp_sa "keycloak-postgres" "keycloak" "sso-postgres"

# Create backup bucket if it doesn't exist
echo "📦 Creating Cloud Storage bucket for backups..."
BACKUP_BUCKET="gs://$PROJECT_ID-sso-backups"
if gsutil ls "$BACKUP_BUCKET" >/dev/null 2>&1; then
  echo "   ✅ Backup bucket already exists"
else
  gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "$BACKUP_BUCKET"
  gsutil versioning set on "$BACKUP_BUCKET"
  echo "   ✅ Backup bucket created with versioning enabled"
fi

# Enable required APIs
echo "🚀 Enabling required Google Cloud APIs..."
gcloud services enable \
  secretmanager.googleapis.com \
  cloudkms.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  --project "$PROJECT_ID"
echo "   ✅ APIs enabled"

echo ""
echo "✅ GSM/KMS setup complete!"
echo ""
echo "📝 Next steps:"
echo "   1. Update Google OAuth credentials: gcloud secrets versions add google-oauth-client-id --data-file=-"
echo "   2. Apply Kubernetes manifests: kubectl apply -f infrastructure/sso/"
echo "   3. Verify workload identity: kubectl describe pod <pod-name> -n keycloak"
echo ""
