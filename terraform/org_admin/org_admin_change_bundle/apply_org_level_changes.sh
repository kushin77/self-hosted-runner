#!/usr/bin/env bash
set -euo pipefail

# apply_org_level_changes.sh
# Usage: --dry-run | --apply

ORGANIZATION_ID="266397081400"
VPC_POLICY_JSON="$(pwd)/terraform/org_admin/org_admin_change_bundle/org_level_vpc_peering_policy.json"

function dry_run() {
  echo "DRY-RUN: Org ID: $ORGANIZATION_ID"
  echo "Preview policy file: $VPC_POLICY_JSON"
  echo
  jq . $VPC_POLICY_JSON || true
  echo
  echo "To apply, run with --apply from an org-admin account."
}

function apply_policy() {
  echo "Applying VPC peering org-policy (will attempt to set-policy)"
  echo "Ensure you are authenticated as an org-admin (gcloud auth list)"

  gcloud resource-manager org-policies set-policy "$VPC_POLICY_JSON" --organization="$ORGANIZATION_ID" --quiet
  echo "Policy applied. Verifying..."
  gcloud resource-manager org-policies describe constraints/compute.restrictVpcPeering --organization="$ORGANIZATION_ID" --format=json

  echo
  echo "Verification commands (copy/paste to run):"
  echo "gcloud resource-manager org-policies describe constraints/compute.restrictVpcPeering --organization=$ORGANIZATION_ID --format=json"
  echo "gcloud resource-manager org-policies list --organization=$ORGANIZATION_ID"
}

if [ "${1:-}" == "--apply" ]; then
  apply_policy
else
  dry_run
fi
