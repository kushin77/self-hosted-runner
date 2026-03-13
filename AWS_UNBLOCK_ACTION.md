AWS Unblock Actions — Immediate Steps
===================================

Context
-------
AWS inventory automation is ready but blocked: Google Secret Manager (GSM) contains placeholder or invalid AWS credentials and the bastion/Vault is not reachable from the Cloud Build worker. To complete the automated, immutable, ephemeral, idempotent, hands-off inventory run we need one of the unblock options below.

Recommended Option A (fastest)
-------------------------------
1. Inject a valid AWS Access Key ID and Secret Access Key into GSM in project `nexusshield-prod`:

```bash
gcloud secrets versions add aws-access-key-id --data-file=- --project=nexusshield-prod <<'EOF'
AKIA...VALID...KEYID
EOF

gcloud secrets versions add aws-secret-access-key --data-file=- --project=nexusshield-prod <<'EOF'
wJalrXUtnFEMI/K7MDENG/bPxRfiCY...VALID...SECRET
EOF
```

2. After adding secrets, I will run the inventory (automated) and commit results.

Option B (ephemeral, recommended for long-term security)
-------------------------------------------------------
1. Enable SSH access for user `akushnir` to the bastion (IP: 192.168.168.42) using the deploy key you trust. Ensure `/root/vault_root_token` exists on the bastion or provide a Vault token via GSM.
2. Once bastion access is enabled I will SSH and configure Vault Agent to render ephemeral AWS creds and run the inventory (no long-lived creds in GSM).

Option C (CI-run)
------------------
Run the prepared Cloud Build that attempts rotation and inventory. Use this command from a network/location that can reach Vault and the bastion if needed:

```bash
gcloud builds submit --project=nexusshield-prod --config=cloudbuild/rotate-credentials-cloudbuild.yaml \
  --substitutions=_BRANCH="portal/immutable-deploy",_REPO_OWNER="kushin77",_REPO_NAME="self-hosted-runner"
```

Notes and safety
----------------
- The `rotate-credentials.sh` script runs in dry-run by default; Cloud Build passes `--apply` inside the build. Review logs before committing output files.
- Option B (Vault ephemeral creds) is preferred for immutable/ephemeral requirements: no long-lived keys in GSM.
- If you choose Option A, rotate or revoke the keys after inventory and replace with ephemeral flow.

What I did now
---------------
- Read `cloudbuild/rotate-credentials-cloudbuild.yaml`, `scripts/secrets/rotate-credentials.sh`, and `scripts/inventory/run-aws-inventory.sh` to confirm behavior.
- Prepared this actionable unblock file and updated the task plan.

Next steps after you act
-----------------------
- If you add GSM secrets (Option A) — I will run the inventory, validate JSON outputs with `jq`, commit `cloud-inventory/aws-*.json`, and close the unblock issue.
- If you enable bastion SSH (Option B) — I will configure Vault Agent, obtain ephemeral creds, run inventory, validate, commit, and close the issue.

Contact
-------
If you want me to proceed immediately, reply with the chosen option (A/B/C) or paste the GSM-ready credentials (they will not be stored in chat). I will proceed and update the repo and issue accordingly.
