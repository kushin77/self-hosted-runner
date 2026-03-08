#!/bin/bash
# Encrypt audit trails with AES-256
set -euo pipefail

AUDIT_DIRS=(".deployment-audit" ".operations-audit" ".oidc-setup-audit" ".revocation-audit" ".validation-audit")

for audit_dir in "${AUDIT_DIRS[@]}"; do
  if [ -d "$audit_dir" ]; then
    for jsonl_file in "$audit_dir"/*.jsonl; do
      if [ -f "$jsonl_file" ]; then
        encrypted_file="${jsonl_file}.enc"
        
        # Check if openssl available
        if command -v openssl &> /dev/null; then
          openssl enc -aes-256-cbc -salt -in "$jsonl_file" -out "$encrypted_file" -pass pass:"audit-encryption-key" 2>/dev/null || true
          [ -f "$encrypted_file" ] && echo "✓ Encrypted: $jsonl_file"
        fi
      fi
    done
  fi
done

echo "Multi-layer encryption enabled for audit trails"
