#!/usr/bin/env bash
set -euo pipefail

# Phase P4 — Generate tenant-specific NetworkPolicies to enforce a deny-all posture with explicit ingress/egress allowances.

TENANT_ID="${1:-}"
OUTPUT_PATH="${2:-/tmp/netpol-${TENANT_ID}.yml}"

if [[ -z "$TENANT_ID" ]]; then
  cat <<'EOF' >&2
Usage: $0 <tenant-id> [<output-path>]
Environment variables:
  ALLOWED_INGRESS_CIDRS (comma-separated)
  ALLOWED_INGRESS_PORTS (comma-separated, defaults to 443)
  ALLOWED_EGRESS_CIDRS (comma-separated)
  ALLOWED_EGRESS_PORTS (comma-separated, defaults to 443)
EOF
  exit 1
fi

normalize_csv() {
  local value="$1"
  local -n target=$2
  target=()
  IFS=',' read -ra tokens <<< "$value" 2>/dev/null || true
  for token in "${tokens[@]}"; do
    token="${token//[[:space:]]/}"
    if [[ -n "$token" ]]; then
      target+=("$token")
    fi
  done
}

normalize_csv "${ALLOWED_INGRESS_CIDRS:-10.30.0.0/16}" ingress_cidrs
normalize_csv "${ALLOWED_INGRESS_PORTS:-443}" ingress_ports
normalize_csv "${ALLOWED_EGRESS_CIDRS:-199.232.0.0/16,10.30.0.0/16,169.254.169.254/32}" egress_cidrs
normalize_csv "${ALLOWED_EGRESS_PORTS:-443,80}" egress_ports

cat <<EOF > "$OUTPUT_PATH"
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: runner-tenant-${TENANT_ID}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

if [[ ${#ingress_cidrs[@]} -gt 0 ]]; then
  cat <<EOF >> "$OUTPUT_PATH"
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-from-trusted
  namespace: runner-tenant-${TENANT_ID}
spec:
  podSelector: {}
  ingress:
  - from:
EOF
  for cidr in "${ingress_cidrs[@]}"; do
    cat <<EOF >> "$OUTPUT_PATH"
    - ipBlock:
        cidr: ${cidr}
EOF
  done
  cat <<EOF >> "$OUTPUT_PATH"
    ports:
EOF
  for port in "${ingress_ports[@]}"; do
    cat <<EOF >> "$OUTPUT_PATH"
    - protocol: TCP
      port: ${port}
EOF
  done
fi

if [[ ${#egress_cidrs[@]} -gt 0 ]]; then
  cat <<EOF >> "$OUTPUT_PATH"
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-to-registries
  namespace: runner-tenant-${TENANT_ID}
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
EOF
  for cidr in "${egress_cidrs[@]}"; do
    cat <<EOF >> "$OUTPUT_PATH"
  - to:
    - ipBlock:
        cidr: ${cidr}
    ports:
EOF
    for port in "${egress_ports[@]}"; do
      cat <<EOF >> "$OUTPUT_PATH"
    - protocol: TCP
      port: ${port}
EOF
    done
  done
fi

echo "Generated tenant policies at $OUTPUT_PATH"
echo "Apply with: kubectl apply -f $OUTPUT_PATH"
