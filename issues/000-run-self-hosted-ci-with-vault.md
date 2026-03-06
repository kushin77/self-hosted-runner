Title: Run self-hosted CI with Vault/AppRole secrets

Context:
- Local fixes and tests passed on developer machine. Need to validate end-to-end on the organization's self-hosted runner.

Goal:
- Run the repository test suite and GitHub Actions workflows on the self-hosted runner with appropriate Vault/AppRole secrets configured securely on the runner host (not in repo).

Actions:
1. Ensure the self-hosted runner host has `VAULT_ADDR`, `VAULT_ROLE_ID`, and `VAULT_SECRET_ID` available via secure environment (runner service/env or Vault agent).
2. Trigger the CI workflows (or run the test scripts directly) on the self-hosted runner.
3. Capture logs and redact any secrets before attaching logs to issues.
4. Open follow-up issues for any failing workflows, attaching redacted logs.

Notes:
- Do NOT paste secret values in any issue or repo file. Use placeholders in reports.
