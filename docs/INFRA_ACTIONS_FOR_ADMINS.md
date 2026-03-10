**INFRA ACTIONS FOR ADMINS — Unblock NexusShield Production**

Purpose: exact commands for infra admins to create the private services connection (required by Cloud SQL private IP) and grant Secret Manager permissions so the provisioning automation can store OPERATOR_SSH_KEY.

Prerequisites:
- You must run these commands as a user or service account with Project Owner / Network Admin privileges and the Service Networking role.
- Ensure the APIs are enabled: `servicenetworking.googleapis.com`, `compute.googleapis.com`, `secretmanager.googleapis.com`, `iam.googleapis.com`.

Step 1 — Create global address and VPC peering

Run (replace PROJECT and NETWORK with your values):

```bash
# from repo root
chmod +x scripts/gcp/create_private_services_connection.sh
./scripts/gcp/create_private_services_connection.sh nexusshield-prod production-portal-vpc google-managed-services-prod-portal 16
```

Notes:
- The script creates the global address and then calls `gcloud services vpc-peerings connect` with `servicenetworking.googleapis.com`.
- If your environment requires additional firewall or DNS steps, perform them per your networking policy.

Step 2 — Grant Secret Manager admin to the provisioning principal

Run (replace PROJECT and SERVICE_ACCOUNT):

```bash
chmod +x scripts/gcp/grant_gsm_secret_admin.sh
./scripts/gcp/grant_gsm_secret_admin.sh nexusshield-prod nexusshield-tfstate-backup@nexusshield-prod.iam.gserviceaccount.com
```

This grants `roles/secretmanager.admin` to the provisioning service account so it can create secrets and add secret versions.

Step 3 — Verify and signal the automation

After Steps 1 and 2 succeed, notify me (or re-run the following from the repo):

```bash
# Re-run terraform finalize and provisioning
TF_VAR_environment=production TF_VAR_gcp_project=nexusshield-prod terraform -chdir=terraform apply -auto-approve
bash scripts/deployment/provision-operator-credentials.sh --no-deploy --verbose
```

If both succeed, the automation will store `OPERATOR_SSH_KEY` in GSM and complete final validation.

Troubleshooting tips:
- If `gcloud services vpc-peerings connect` reports permissions errors, ensure the caller has `roles/servicenetworking.admin` or Project Owner.
- If `gcloud compute addresses create` errors about `--network`, provide the correct VPC name and confirm the VPC exists.
- For Secret Manager errors, ensure `secretmanager.googleapis.com` is enabled and the caller has `roles/secretmanager.admin`.

Contact: tag `#2323` in the repo issues and paste command outputs for quick follow-up.

Required roles for an infra admin
---------------------------------

The caller that runs the unblock steps must have sufficient permissions. Recommended minimal roles (assign to an admin account or use a temporary elevated session):

- `roles/compute.networkAdmin` (create global addresses and manage networks)
- `roles/servicenetworking.admin` (create VPC peering / private services connections)
- `roles/secretmanager.admin` (create secrets and secret versions)
- `roles/iam.securityAdmin` or `roles/resourcemanager.projectIamAdmin` (only if you need to modify IAM bindings)

Single-line paste for infra admins
---------------------------------

Copy-pasteable command (run as an account with the roles above). Replace `PROJECT` and `NETWORK` as needed.

```bash
PROJECT=nexusshield-prod; NETWORK=production-portal-vpc; RANGE=google-managed-services-${PROJECT}; \
chmod +x scripts/gcp/create_private_services_connection.sh scripts/gcp/grant_gsm_secret_admin.sh && \
./scripts/gcp/create_private_services_connection.sh ${PROJECT} ${NETWORK} ${RANGE} 16 && \
./scripts/gcp/grant_gsm_secret_admin.sh ${PROJECT} nexusshield-tfstate-backup@${PROJECT}.iam.gserviceaccount.com && \
TF_VAR_environment=production TF_VAR_gcp_project=${PROJECT} terraform -chdir=terraform apply -auto-approve && \
bash scripts/deployment/provision-operator-credentials.sh --no-deploy --verbose
```

If any of these steps fail due to permission errors, collect the `/tmp/*.log` files and attach them to issue `#2323` for follow-up.

## Final Handoff Actions for Host-admins and Cloud-team

This section lists the exact, auditable commands the host-admin and cloud-team must run to complete the final go-live. Follow these steps exactly and paste the full output logs as comments to the corresponding GitHub issues so the repository automation can verify and close them.

1) Host-admin (Issue #2310) — system-level orchestrator install

 - Purpose: Install systemd timers and system-level helpers required to run the orchestrator and credential rotation.
 - Run as the host-admin on the fullstack production host (192.168.168.42). This requires sudo.

Commands to run (copy/paste):

```bash
cd /home/runner/self-hosted-runner || cd /home/akushnir/self-hosted-runner
sudo bash scripts/orchestration/run-system-install.sh |& tee /tmp/deploy-orchestrator-$(date -u +%Y%m%dT%H%M%SZ).log
cat /tmp/deploy-orchestrator-*.log
```

What to paste to Issue #2310:
- Paste the complete contents of `/tmp/deploy-orchestrator-*.log` as a single comment.

What the repo automation will do:
- The verifier will save the posted log, compute its SHA256, post an audit comment with the SHA, run basic heuristics (systemd enabled/started lines), and automatically close Issue #2310 when checks pass.

2) Cloud-team (Issue #2311) — cloud finalization & KMS checks

 - Purpose: Provide final credentials and run the cloud finalize script which performs Terraform applies, KMS key checks and final resource provisioning.
 - Ensure the environment has GCP service-account credentials with permissions for GSM and KMS and that AWS KMS access is available where required.

Commands to run (copy/paste):

```bash
cd /home/runner/self-hosted-runner || cd /home/akushnir/self-hosted-runner
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
bash scripts/go-live-kit/02-deploy-and-finalize.sh |& tee /tmp/go-live-finalize-$(date -u +%Y%m%dT%H%M%SZ).log
cat /tmp/go-live-finalize-*.log
```

What to paste to Issue #2311:
- Paste the complete contents of `/tmp/go-live-finalize-*.log` as a single comment.

What the repo automation will do:
- The verifier will save the posted log, compute SHA256, post an audit comment with the SHA, run basic heuristics (Terraform apply complete, containers deployed), and automatically close Issue #2311 when checks pass.
- The verifier will save the posted log, compute SHA256, post an audit comment with the SHA, run basic heuristics (Terraform apply complete, containers deployed), and automatically close Issue #2311 when checks pass.

## Operator One-Run Deployment (recommended)

Use this flow when you want a single, auditable command on the deployment host to validate prerequisites, deploy the stack, run basic health checks, optionally run integration tests, and collect logs.

Steps (run from your workstation):

```bash
# 1. Copy production env and GCP service account to the deployment host
scp .env.production runner@192.168.168.42:/home/runner/.env.production
scp /path/to/service-account-key.json runner@192.168.168.42:/home/runner/service-account-key.json
ssh runner@192.168.168.42 'chmod 600 /home/runner/service-account-key.json'

# 2. Run the remote deploy-and-validate script on the host
ssh runner@192.168.168.42 'cd /home/akushnir/self-hosted-runner && bash scripts/deployment/remote-deploy-and-validate.sh'
```

What the script does (on-host):
- Runs `scripts/validate-deployment.sh` with `DEPLOYMENT_HOST=192.168.168.42`.
- Uses `docker-compose` to build and start services, then waits for health endpoints (backend: `http://localhost:3000/health`, frontend: `http://localhost:13000/`).
- Runs `scripts/test-portal.sh` if present.
- Saves logs under `/home/runner/deploy-logs/<timestamp>` and appends an audit entry to `logs/deployment/audit.jsonl`.

If you receive "Permission denied" on SSH, ensure your key is present in `/home/runner/.ssh/authorized_keys` on the deployment host and that the `runner` account is allowed to run the commands.

Verification notes (for auditors):
- All posted logs are saved and their SHA256 values are posted to the issue before closing.
- Audit entries are appended to `logs/deployment/audit.jsonl` with timestamp, actor, action and `report` path. The entries are committed to the repo and pushed to `main`.
- If verification fails the verifier posts a diagnostic comment explaining which heuristics failed; re-run the command and re-post the full log.

Immediate next steps (summary):
- Host-admin: run the system install command above and paste the `/tmp/deploy-orchestrator-*.log` to Issue #2310.
- Cloud-team: run the finalize command above and paste `/tmp/go-live-finalize-*.log` to Issue #2311.

---

DEPLOYMENT STATUS NOTE

The NexusShield Portal backend deployment was completed and verified on 2026-03-10. The production host (192.168.168.42) is running the backend, database and cache services; the deployment audit and verification logs have been saved to the repository under `logs/deployment/`.

Recommended immediate actions for infra:

- Execute Steps 1–2 in this document to create the private services connection and grant Secret Manager permissions.
- Re-run the finalize commands below to let the automation store `OPERATOR_SSH_KEY` and complete final validation.

Commands to re-run:

```bash
# Re-run terraform finalize and provisioning
TF_VAR_environment=production TF_VAR_gcp_project=nexusshield-prod terraform -chdir=terraform apply -auto-approve
bash scripts/deployment/provision-operator-credentials.sh --no-deploy --verbose
```

If you prefer, I can run the finalize commands once you confirm infra permissions are in place. Otherwise, run the commands above and paste the finalize log to Issue #2311 for automated verification.

