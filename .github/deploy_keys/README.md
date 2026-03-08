This directory stores deployment keys for historical purposes. It must never contain live private keys in the repository.

Remediation policy:
- Remove any private keys from this directory and store them in a secrets manager (GSM, Vault, or AWS KMS-backed secret store).
- If a key is removed from the repository, rotate/revoke the corresponding credential immediately and update deployment configs to reference the secret store.

If you found this README because an automated remediation removed a file, follow the steps in the remediation report and the associated PR.
