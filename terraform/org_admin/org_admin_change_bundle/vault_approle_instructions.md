Vault AppRole Provisioning (for Vault Admins)
=============================================

Purpose
-------
Provision an AppRole for `prod-deployer` to allow short-lived Vault tokens for deployments.

Steps (Vault admin)
-------------------
1. Enable approle auth (if not already enabled):

```bash
vault auth enable approle
```

2. Create role with limited policies:

```bash
vault write auth/approle/role/prod-deployer-role \
  token_ttl=1h token_max_ttl=4h secret_id_ttl=0 \
  policies="prod-deployer"
```

3. Retrieve role_id and secret_id and store in Secret Manager:

```bash
ROLE_ID=$(vault read -field=role_id auth/approle/role/prod-deployer-role/role-id)
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/prod-deployer-role/secret-id)

# Store in GSM (org-admin / secret-manager-admin required)
# gcloud secrets create vault-approle-id --project=nexusshield-prod || true
# echo "$ROLE_ID" | gcloud secrets versions add vault-approle-id --project=nexusshield-prod --data-file=-
# gcloud secrets create vault-approle-secret --project=nexusshield-prod || true
# echo "$SECRET_ID" | gcloud secrets versions add vault-approle-secret --project=nexusshield-prod --data-file=-
```

Verification
------------
Use the stored AppRole to perform a login and verify token is returned.

```bash
ROLE_ID=$(gcloud secrets versions access latest --secret=vault-approle-id --project=nexusshield-prod)
SECRET_ID=$(gcloud secrets versions access latest --secret=vault-approle-secret --project=nexusshield-prod)

curl -s -X POST https://<VAULT_ADDR>/v1/auth/approle/login -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" | jq .
```
