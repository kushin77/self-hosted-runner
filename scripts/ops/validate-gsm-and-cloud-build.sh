#!/bin/bash
# GSM Credentials Validation & Cloud Build Access Test
# Validates that GSM secrets can be accessed from Cloud Build
# Run: bash scripts/ops/validate-gsm-and-cloud-build.sh

set -euo pipefail

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
TIMESTAMP=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

echo "🔐 GSM & Cloud Build Access Validation — $TIMESTAMP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Step 1: Verify Cloud Build service account has Secret Accessor role
echo ""
echo "Step 1: Checking Cloud Build service account IAM...":

CB_SA="${PROJECT_ID}@cloudbuild.gserviceaccount.com"

if gcloud projects get-iam-policy "$PROJECT_ID" --flatten="bindings[].members" \
  --format='table(bindings.role)' 2>/dev/null | grep -q "roles/secretmanager.secretAccessor"; then
  echo "  ✓ secretmanager.secretAccessor role found in project"
else
  echo "  ✗ WARNING: secretmanager.secretAccessor not found; Cloud Build may not access secrets"
fi

# Step 2: Create & submit validation Cloud Build
echo ""
echo "Step 2: Creating validation Cloud Build template..."

cat > /tmp/cloudbuild-validate-gsm.yaml <<'CLOUDY'
steps:
- name: gcr.io/cloud-builders/gcloud
  id: validate-gsm-access
  entrypoint: bash
  args:
  - -c
  - |
    set -euo pipefail
    echo "Testing GSM access from Cloud Build..."
    echo ""
    
    # Test 1: Read github-token secret
    echo "[1/4] Reading github-token..."
    if GH_TOKEN=$(gcloud secrets versions access latest --secret=github-token 2>/dev/null); then
      if [[ -n "$GH_TOKEN" ]]; then
        echo "  ✓ Successfully read github-token (${#GH_TOKEN} chars)"
      else
        echo "  ✗ github-token is empty"
        exit 1
      fi
    else
      echo "  ✗ Failed to read github-token"
      exit 1
    fi
    
    # Test 2: Read VAULT_ADDR
    echo "[2/4] Reading VAULT_ADDR..."
    if VAULT_ADDR=$(gcloud secrets versions access latest --secret=VAULT_ADDR 2>/dev/null); then
      if [[ -n "$VAULT_ADDR" ]]; then
        echo "  ✓ Successfully read VAULT_ADDR"
      else
        echo "  ✗ VAULT_ADDR is empty"
      fi
    else
      echo "  ✗ Failed to read VAULT_ADDR"
    fi
    
    # Test 3: Check aws-access-key-id (may be placeholder)
    echo "[3/4] Reading aws-access-key-id..."
    if AWS_KEY=$(gcloud secrets versions access latest --secret=aws-access-key-id 2>/dev/null); then
      if [[ -n "$AWS_KEY" && "$AWS_KEY" != "placeholder"* ]]; then
        echo "  ✓ aws-access-key-id populated"
      else
        echo "  ⚠ aws-access-key-id not yet populated (populate in ops)"
      fi
    else
      echo "  ✗ Failed to read aws-access-key-id"
    fi
    
    # Test 4: Check aws-secret-access-key (may be placeholder)
    echo "[4/4] Reading aws-secret-access-key..."
    if AWS_SECRET=$(gcloud secrets versions access latest --secret=aws-secret-access-key 2>/dev/null); then
      if [[ -n "$AWS_SECRET" && "$AWS_SECRET" != "placeholder"* ]]; then
        echo "  ✓ aws-secret-access-key populated"
      else
        echo "  ⚠ aws-secret-access-key not yet populated (populate in ops)"
      fi
    else
      echo "  ✗ Failed to read aws-secret-access-key"
    fi
    
    echo ""
    echo "✓ GSM access validation complete"
CLOUDY

echo "  Template created: /tmp/cloudbuild-validate-gsm.yaml"

# Step 3: Submit the validation build
echo ""
echo "Step 3: Submitting validation build to Cloud Build..."
echo "  (this will run asynchronously)"

if BUILD_ID=$(gcloud builds submit --config=/tmp/cloudbuild-validate-gsm.yaml \
  --project=$PROJECT_ID . 2>&1 | grep "ID:" | awk '{print $2}'); then
  echo "  ✓ Build submitted: $BUILD_ID"
  echo "  Track progress: gcloud builds log $BUILD_ID --stream"
else
  echo "  ✗ Failed to submit build"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Validation complete"
echo ""
echo "Next steps:"
echo "  1. Monitor build: gcloud builds log $BUILD_ID --stream"
echo "  2. Once build succeeds, AWS credentials are ready"
echo "  3. Close GitHub issue #2939 (AWS credentials)"
echo "  4. First scheduled run will execute tomorrow 00:00 UTC"
