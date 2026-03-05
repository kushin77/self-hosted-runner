#!/usr/bin/env bash
# Bootstrap air-gapped RunnerCloud control plane in a customer cluster.
# This script only outlines the steps; real deployment should use Terraform/helm.
# Usage: ./scripts/airgap_setup.sh <namespace>
set -euo pipefail

NS=${1:-runnercloud}

echo "Creating namespace $NS"
kubectl create namespace "$NS" || true

# apply simple network policy restricting egress
cat <<'EOF' | kubectl apply -n "$NS" -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-egress-by-default
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {} # allow intra-namespace
    ports:
    - protocol: TCP
      port: 443
EOF

echo "Namespace and basic network policy created."

echo "Note: add GitHub.com and cloud API CIDRs to egress allowlist manually."

echo "Deploy control plane components (API server, queue, scaler) here..."

echo "Audit logs will be written to bucket \$AUDIT_BUCKET or /var/log/rc-audit.json"
