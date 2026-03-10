#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT_LOG="${REPO_ROOT}/logs/direct-provisioning-audit.jsonl"

audit() {
    echo "{\"timestamp\":\"$(date -u +'%Y-%m-%dT%H:%M:%SZ')\",\"operation\":\"$1\",\"status\":\"$2\",\"message\":\"$3\",\"commit\":\"$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo 'unknown')\"}" >> "$AUDIT_LOG"
}

# Fetch from Vault
if [ -n "${VAULT_ADDR:-}" ]; then
    echo "Fetching kubeconfig from Vault..."
    
    CA_CERT=$(vault kv get -field=ca_cert secret/k8s-credentials 2>/dev/null || echo "")
    CLIENT_CERT=$(vault kv get -field=client_cert secret/k8s-credentials 2>/dev/null || echo "")
    CLIENT_KEY=$(vault kv get -field=client_key secret/k8s-credentials 2>/dev/null || echo "")
    
    if [ -n "$CA_CERT" ] && [ -n "$CLIENT_CERT" ] && [ -n "$CLIENT_KEY" ]; then
        cat > /tmp/staging.kubeconfig <<KUBECONFIG
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $(echo -n "$CA_CERT" | base64 -w0)
    server: https://k8s.p4.io:6443
  name: p4-cluster
contexts:
- context:
    cluster: p4-cluster
    user: ci-runner
  name: p4-context
current-context: p4-context
users:
- name: ci-runner
  user:
    client-certificate-data: $(echo -n "$CLIENT_CERT" | base64 -w0)
    client-key-data: $(echo -n "$CLIENT_KEY" | base64 -w0)
KUBECONFIG
        
        chmod 600 /tmp/staging.kubeconfig
        cp /tmp/staging.kubeconfig "${REPO_ROOT}/staging.kubeconfig"
        audit "provision-kubeconfig" "success" "Kubeconfig provisioned from Vault"
        echo "✅ Kubeconfig provisioned"
        exit 0
    fi
fi

audit "provision-kubeconfig" "blocked" "Vault credentials not available"
echo "⏳ Kubeconfig provisioning blocked - awaiting credentials"
exit 1
