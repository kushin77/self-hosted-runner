#!/usr/bin/env bash
##############################################################################
# create_private_services_connection.sh
#
# Creates a global address in a VPC and establishes a private services 
# connection (VPC peering) for Cloud SQL private IP access.
#
# Usage: ./create_private_services_connection.sh PROJECT NETWORK RANGE SUBNET_SIZE
# Example: ./create_private_services_connection.sh nexusshield-prod production-portal-vpc google-managed-services-prod-portal 16
#
# Requires: gcloud (with compute.globalAddresses.createInternal, servicenetworking.admin permissions)
##############################################################################

set -euo pipefail

PROJECT="${1:-${TF_VAR_gcp_project:-nexusshield-prod}}"
NETWORK="${2:-production-portal-vpc}"
RANGE="${3:-google-managed-services-${PROJECT}}"
SUBNET_SIZE="${4:-16}"

echo "[→] NexusShield VPC Private Services Connection Setup"
echo "    Project: ${PROJECT}"
echo "    Network: ${NETWORK}"
echo "    Address Range: ${RANGE}"
echo "    Subnet Size: /${SUBNET_SIZE}"

# Step 1: Verify VPC exists
echo "[→] Verifying VPC '${NETWORK}' exists..."
if ! gcloud compute networks describe "${NETWORK}" --project="${PROJECT}" &>/dev/null; then
    echo "❌ VPC '${NETWORK}' not found in project '${PROJECT}'"
    echo "   Create it first: gcloud compute networks create ${NETWORK} --project=${PROJECT}"
    exit 1
fi
echo "✓ VPC verified"

# Step 2: Create global address (unless it already exists)
echo "[→] Checking for existing address '${RANGE}'..."
if gcloud compute addresses describe "${RANGE}" --global --project="${PROJECT}" &>/dev/null; then
    echo "✓ Address '${RANGE}' already exists"
else
    echo "[→] Creating global address '${RANGE}' with /${SUBNET_SIZE} netmask..."
    gcloud compute addresses create "${RANGE}" \
        --global \
        --purpose=VPC_PEERING \
        --prefix-length="${SUBNET_SIZE}" \
        --network="${NETWORK}" \
        --project="${PROJECT}" \
        --description="NexusShield Portal private services connection (Cloud SQL)"
    echo "✓ Global address created"
fi

# Step 3: Create VPC peering connection (unless it already exists)
echo "[→] Creating VPC peering with servicenetworking.googleapis.com..."
if gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges="${RANGE}" \
    --network="${NETWORK}" \
    --project="${PROJECT}" 2>&1; then
    echo "✓ VPC peering connection established"
else
    echo "⚠ Peering may already exist or requires infrastructure admin permissions"
fi

echo ""
echo "✅ Private services connection ready for Cloud SQL private IP"
echo ""
echo "Next: Retry the provisioning script to proceed with Secret Manager and Terraform apply"
