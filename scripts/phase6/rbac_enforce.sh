#!/usr/bin/env bash
set -euo pipefail

# RBAC enforcement helper — audit current cluster RBAC and apply minimal policies.
# WARNING: Run in staging first. This script is idempotent and will not remove existing bindings without explicit approval.

echo "Listing clusterroles with wide permissions..."
kubectl get clusterroles -o json | jq '.items[] | {name:.metadata.name, rules:.rules}' | sed -n '1,80p'

echo "(Placeholder) Apply least-privilege policies from 'phase6/rbac_policies/'"
if [ -d "phase6/rbac_policies" ]; then
  for f in phase6/rbac_policies/*.yaml; do
    echo "Applying $f"
    kubectl apply -f "$f" || true
  done
else
  echo "No rbac_policies directory found; create policies under phase6/rbac_policies/"
fi

echo "RBAC enforcement complete (placeholder). Review applied policies manually before production rollout."
