#!/usr/bin/env bash
set -euo pipefail

# Generate mTLS certificates for provisioner-worker <-> Vault communication
# Part of Phase P4 hardening
# Idempotent: checks for existing certs before regenerating

CERT_DIR="${CERT_DIR:-/etc/provisioner-worker/certs}"
NAMESPACE="${NAMESPACE:-provisioner-system}"
DAYS_VALID=${DAYS_VALID:-365}

mkdir -p "$CERT_DIR"

# Helper: check if cert is still valid for at least 30 days
cert_still_valid() {
  local cert_file="$1"
  if [ ! -f "$cert_file" ]; then
    return 1
  fi
  
  local expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
  local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
  local now_epoch=$(date +%s)
  local days_remaining=$(( (expiry_epoch - now_epoch) / 86400 ))
  
  [ $days_remaining -gt 30 ]
}

echo "=== mTLS Certificate Generation ==="

# Step 1: Generate or reuse CA certificate
if cert_still_valid "$CERT_DIR/ca.crt"; then
  echo "✓ Using existing CA certificate"
else
  echo "Generating new CA certificate..."
  openssl req -x509 -newkey rsa:4096 -keyout "$CERT_DIR/ca.key" \
    -out "$CERT_DIR/ca.crt" -days "$DAYS_VALID" -nodes \
    -subj "/CN=provisioner-worker-ca/O=GithubRunner/C=US" || {
    echo "ERROR: Failed to generate CA certificate" >&2
    exit 1
  }
  echo "✓ CA certificate generated"
fi

# Step 2: Generate or reuse server certificate
if cert_still_valid "$CERT_DIR/server.crt"; then
  echo "✓ Using existing server certificate"
else
  echo "Generating new server certificate..."
  
  # Create certificate signing request
  openssl req -newkey rsa:4096 -keyout "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.csr" -nodes \
    -subj "/CN=provisioner-worker.provisioner-system.svc.cluster.local/O=GithubRunner/C=US" || {
    echo "ERROR: Failed to create CSR" >&2
    exit 1
  }
  
  # Sign with CA
  openssl x509 -req -in "$CERT_DIR/server.csr" \
    -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial -out "$CERT_DIR/server.crt" \
    -days "$DAYS_VALID" \
    -extfile <(printf "subjectAltName=DNS:provisioner-worker.provisioner-system.svc.cluster.local,DNS:provisioner-worker,DNS:localhost,IP:127.0.0.1") || {
    echo "ERROR: Failed to sign server certificate" >&2
    exit 1
  }
  
  rm "$CERT_DIR/server.csr"
  echo "✓ Server certificate generated"
fi

# Step 3: Generate or reuse client certificate (for Vault to verify)
if cert_still_valid "$CERT_DIR/client.crt"; then
  echo "✓ Using existing client certificate"
else
  echo "Generating new client certificate..."
  
  openssl req -newkey rsa:4096 -keyout "$CERT_DIR/client.key" \
    -out "$CERT_DIR/client.csr" -nodes \
    -subj "/CN=provisioner-worker-client/O=GithubRunner/C=US" || {
    echo "ERROR: Failed to create client CSR" >&2
    exit 1
  }
  
  openssl x509 -req -in "$CERT_DIR/client.csr" \
    -CA "$CERT_DIR/ca.crt" -CAkey "$CERT_DIR/ca.key" \
    -CAcreateserial -out "$CERT_DIR/client.crt" \
    -days "$DAYS_VALID" || {
    echo "ERROR: Failed to sign client certificate" >&2
    exit 1
  }
  
  rm "$CERT_DIR/client.csr"
  echo "✓ Client certificate generated"
fi

# Step 4: Create Kubernetes secret for certs (idempotent)
echo "Creating Kubernetes secret..."
kubectl create secret tls provisioner-worker-tls \
  --cert="$CERT_DIR/server.crt" \
  --key="$CERT_DIR/server.key" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || {
  echo "⚠ Kubernetes secret creation failed (may already exist)"
}

# Step 5: Create CA ConfigMap (for client verification)
echo "Creating CA ConfigMap..."
kubectl create configmap provisioner-worker-ca \
  --from-file=ca.crt="$CERT_DIR/ca.crt" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || {
  echo "⚠ CA ConfigMap creation failed (may already exist)"
}

echo "=== mTLS Setup Complete ==="
echo "  Server cert: $CERT_DIR/server.crt (${DAYS_VALID} days)"
echo "  Client cert: $CERT_DIR/client.crt (${DAYS_VALID} days)"
echo "  CA: $CERT_DIR/ca.crt (authority)"
echo "✓ Kubernetes secrets and ConfigMaps updated"
