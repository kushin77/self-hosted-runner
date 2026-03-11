Secret Fetch Helper (OIDC → GSM → Vault → KMS)

Overview
- This helper script `scripts/secrets/fetch-secret-oidc-gsm-vault.sh` attempts to retrieve secrets from the canonical chain:
  1. Google Secret Manager (GSM)
  2. HashiCorp Vault (OIDC login or AppRole)
  3. Cloud KMS decrypt (optional, for ciphertext via stdin)

Usage
- GSM (preferred if available):
  ```bash
  GSM_PROJECT=my-gcp-project GSM_SECRET_NAME=my-secret \
    ./scripts/secrets/fetch-secret-oidc-gsm-vault.sh
  ```

- Vault (OIDC):
  ```bash
  VAULT_ADDR=https://vault.example.com VAULT_OIDC_ROLE=my-role \
    VAULT_SECRET_PATH=secret/data/myapp ./scripts/secrets/fetch-secret-oidc-gsm-vault.sh
  ```

- Vault (AppRole):
  ```bash
  VAULT_ADDR=https://vault.example.com VAULT_ROLE_ID=... VAULT_SECRET_ID=... \
    VAULT_SECRET_PATH=secret/data/myapp ./scripts/secrets/fetch-secret-oidc-gsm-vault.sh
  ```

- KMS decrypt (ciphertext on stdin):
  ```bash
  KMS_PROJECT=... KMS_LOCATION=... KMS_KEYRING=... KMS_KEY=... \
    ./scripts/secrets/fetch-secret-oidc-gsm-vault.sh < ciphertext.bin
  ```

Security notes
- The script prints secret plaintext to stdout. Pipe into a consumer, avoid logging.
- This helper is intentionally minimal; for production use, wrap it in a short-lived runtime and ensure secrets never land in logs.

Next steps
- Optionally add a small wrapper that integrates with deployment tooling to fetch secrets at deploy-time using OIDC and return values via process substitution (safer than environment leaks).