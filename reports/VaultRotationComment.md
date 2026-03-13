Vault rotation attempt ran but failed to contact Vault (curl: could not resolve host).

Log saved in repository: logs/rotate-vault-*.log

Action required:
- Provide reachable `VAULT_ADDR` (HTTPS) and ensure network access to Vault from Cloud Build and runners.
- Confirm IAM: Cloud Build SA needs `secretAccessor` on `VAULT_ADDR` and `VAULT_TOKEN`.

See `reports/HISTORY_PURGE_AUDIT_20260313.md` for context and audit details.