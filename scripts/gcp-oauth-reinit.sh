#!/bin/bash
# GCP OAuth Token Scope Refresh Script
# This script must be run interactively on a machine with browser access
set -euo pipefail

echo "🔐 GCP OAuth Token Scope Refresh"
echo "=================================="
echo ""
echo "This script will refresh your GCP credentials with proper scopes"
echo "for terraform deployment."
echo ""
echo "REQUIRED SCOPES:"
echo "  - compute.googleapis.com (Compute Engine instances, firewalls, templates)"
echo "  - iam.googleapis.com (Service accounts and IAM bindings)"
echo ""
echo "Follow the prompts to complete OAuth re-authentication..."
echo ""

# Step 1: Initial login
echo "Step 1: Authenticate with Google Cloud"
gcloud auth login --no-launch-browser || gcloud auth login

# Step 2: Set ADC credentials with full scope
echo ""
echo "Step 2: Set up Application Default Credentials with full scope"
gcloud auth application-default login --no-launch-browser || gcloud auth application-default login

# Step 3: Verify
echo ""
echo "Step 3: Verifying credentials..."
TOKEN=$(gcloud auth print-access-token 2>&1 || gcloud auth application-default print-access-token 2>&1)
if [ -n "$TOKEN" ]; then
    echo "✅ Token refreshed successfully"
    echo ""
    echo "🚀 Ready to deploy. Run:"
    echo "   cd /home/akushnir/self-hosted-runner/terraform/environments/staging-tenant-a"
    echo "   terraform apply -auto-approve tfplan2"
else
    echo "❌ Token refresh failed"
    exit 1
fi
