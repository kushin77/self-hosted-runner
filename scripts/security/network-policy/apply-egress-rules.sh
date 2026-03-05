#!/bin/bash
# Phase P4: Baseline Deny-All Network Policy Application
# This script applies isolated egress/ingress rules for the given tenant ID.

TENANT_ID="$1"
NAMESPACE="runner-tenant-${TENANT_ID}"

if [[ -z "$TENANT_ID" ]]; then
  echo "Usage: $0 <tenant_id>"
  exit 1
fi

echo "Applying baseline 'deny-all' egress networking for tenant: $TENANT_ID"

# 1. Create Tenant Metadata (Namespace or Tagging logic)
# This mockup assumes K8s style or GCP VPC Service Control logic for partitioning.

# Example: Calico Enterprise Egress Rule Configuration
cat <<EOF > /tmp/netpol-${TENANT_ID}.yml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-registry-access
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0 # Restricted registry IP range (mock placeholder)
    ports:
    - protocol: TCP
      port: 443
EOF

echo "✓ Baseline networking policy drafted to /tmp/netpol-${TENANT_ID}.yml"
echo "Next: Apply using 'kubectl apply -f /tmp/netpol-${TENANT_ID}.yml' in maintenance window."
