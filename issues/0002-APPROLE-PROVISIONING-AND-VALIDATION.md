Title: ACTION: Create AppRole `automation-runner` and validate vault_sync
Status: open
Labels: automation, security, task, phase-5
Milestone: Phase 5 (Multi-Cloud Vault Integration)
Blocker-for-Milestone-4: NO — Phase 5 contingent on 0001-REQUEST completion

Summary
-------
Automate AppRole creation (or confirm operator-run), validate Cloud Run `vault_sync` endpoint succeeds, and close the operator request issue when done.

Steps
-----
1. Ensure `VAULT_ADDR` is set in `terraform/terraform.tfvars` or environment.
2. Authenticate to Vault and run the provisioning script:

```bash
export PROJECT=nexusshield-prod
export VAULT_ADDR="https://<vault.example.com>"
# Use an interactive `vault login` (or equivalent) in this shell, then:
bash ./scripts/vault/create_approle_and_store.sh
```

3. Verify GSM contains secrets `automation-runner-vault-role-id` and `automation-runner-vault-secret-id`.
4. Trigger Cloud Run vault_sync (authenticated identity-token) to confirm writing to Vault:

```bash
TOKEN=$(gcloud auth print-identity-token)
curl -s -H "Authorization: Bearer $TOKEN" -X POST https://<automation-runner-url>/ -d '{"action":"vault_sync","secret":"production-portal-db-username","path":"secret/smoke-test"}'
```

5. If verification passes, update this issue to `status: closed` and close `0001-REQUEST-VAULT-ADDR-AND-ADMIN-TOKEN.md`.

Assignee: @operator / @automation
