#!/usr/bin/env bash
# GCP Permission Validator - Verify service account has required IAM roles
# Usage: ./validate-gcp-permissions.sh [--project PROJECT_ID] [--account SERVICE_ACCOUNT_EMAIL] [--check-only]

set -euo pipefail

# Default values
PROJECT_ID="${GCP_PROJECT_ID:-}"
SERVICE_ACCOUNT="${GCP_SERVICE_ACCOUNT_EMAIL:-}"
CHECK_ONLY="false"
VERBOSE="false"

# Required roles for Phase P2/P3 infrastructure
REQUIRED_ROLES=(
  "roles/compute.networkAdmin"
  "roles/compute.securityAdmin"
  "roles/storage.admin"
  "roles/cloudkms.cryptoKeyUser"
  "roles/iam.securityAdmin"
  "roles/resourcemanager.projectIamAdmin"
)

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_ID="$2"
      shift 2
      ;;
    --account)
      SERVICE_ACCOUNT="$2"
      shift 2
      ;;
    --check-only)
      CHECK_ONLY="true"
      shift
      ;;
    --verbose)
      VERBOSE="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Validate inputs
if [ -z "$PROJECT_ID" ]; then
  echo "❌ GCP_PROJECT_ID not set. Use --project or set GCP_PROJECT_ID env var"
  exit 1
fi

if [ -z "$SERVICE_ACCOUNT" ]; then
<REDACTED_SECRET_REMOVED_BY_AUTOMATION>
  exit 1
fi

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║          GCP PERMISSION VALIDATOR - SERVICE ACCOUNT CHECK          ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Project ID: $PROJECT_ID"
echo "Service Account: $SERVICE_ACCOUNT"
echo "Mode: $([ "$CHECK_ONLY" = "true" ] && echo "Check-only" || echo "Full validation")"
echo ""

# Check if gcloud is available
if ! command -v gcloud &> /dev/null; then
  echo "❌ gcloud CLI not found. Install Google Cloud SDK: https://cloud.google.com/sdk/install"
  exit 1
fi

# Get current project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
  echo "⚠️  Current project: $CURRENT_PROJECT (expected: $PROJECT_ID)"
  echo "🔄 Setting project to $PROJECT_ID..."
  gcloud config set project "$PROJECT_ID" || {
    echo "❌ Failed to set GCP project. Check credentials and permissions."
    exit 1
  }
fi

echo "✓ Project set to $PROJECT_ID"
echo ""

# Verify service account exists
echo "📋 Verifying service account exists..."
if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT" --project="$PROJECT_ID" &>/dev/null; then
  echo "❌ Service account not found: $SERVICE_ACCOUNT"
  echo "Available service accounts:"
  gcloud iam service-accounts list --project="$PROJECT_ID" --format="value(email)"
  exit 1
fi
echo "✓ Service account exists"
echo ""

# Get current roles
echo "🔍 Checking assigned roles..."
CURRENT_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:$SERVICE_ACCOUNT" \
  --format="value(bindings.role)" 2>/dev/null || echo "")

if [ -z "$CURRENT_ROLES" ]; then
  echo "⚠️  No roles found for service account"
  echo ""
  echo "Required roles (MISSING ALL):"
  for role in "${REQUIRED_ROLES[@]}"; do
    echo "  ❌ $role"
  done
  exit 1
fi

# Check required roles
MISSING_ROLES=()
FOUND_ROLES=()

echo "Checking $((${#REQUIRED_ROLES[@]} )) required roles..."
echo ""

for role in "${REQUIRED_ROLES[@]}"; do
  if echo "$CURRENT_ROLES" | grep -q "^$role$"; then
    echo "  ✓ $role"
    FOUND_ROLES+=("$role")
  else
    echo "  ❌ $role"
    MISSING_ROLES+=("$role")
  fi
done

echo ""
echo "═════════════════════════════════════════════════════════════════════"
echo "Summary:"
echo "  Required roles: ${#REQUIRED_ROLES[@]}"
echo "  Found roles: ${#FOUND_ROLES[@]}"
echo "  Missing roles: ${#MISSING_ROLES[@]}"
echo ""

if [ ${#MISSING_ROLES[@]} -eq 0 ]; then
  echo "✅ ALL REQUIRED ROLES FOUND"
  echo ""
  echo "Current role assignments:"
  echo "$CURRENT_ROLES" | sed 's/^/  /'
  echo ""
  echo "✓ Service account is ready for Phase P2/P3 terraform apply"
  exit 0
else
  echo "❌ MISSING ROLES DETECTED"
  echo ""
  echo "Missing roles that must be added:"
  for role in "${MISSING_ROLES[@]}"; do
    echo "  • $role"
  done
  echo ""
  
  if [ "$CHECK_ONLY" = "false" ]; then
    echo "Additional roles found (not required):"
    # Show roles that are assigned but not in our required list
    echo "$CURRENT_ROLES" | while read -r role; do
      if ! printf '%s\n' "${REQUIRED_ROLES[@]}" | grep -q "^$role$"; then
        echo "  • $role"
      fi
    done
  fi
  
  echo ""
  echo "To add missing roles, run:"
  for role in "${MISSING_ROLES[@]}"; do
    echo "  gcloud projects add-iam-policy-binding $PROJECT_ID \\"
    echo "    --member=serviceAccount:$SERVICE_ACCOUNT \\"
    echo "    --role=$role"
  done
  echo ""
  
  exit 1
fi
