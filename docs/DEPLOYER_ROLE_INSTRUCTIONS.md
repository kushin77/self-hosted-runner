# Deployer Role & Bootstrap Instructions

This document contains step-by-step instructions for Project Owners to bootstrap the deployer service account and related IAM artifacts required by the `prevent-releases` orchestrator.

Recommended: run `infra/grant-orchestrator-roles.sh` as a Project Owner. This script is idempotent and will:

- Grant `roles/run.admin`, `roles/iam.serviceAccountAdmin`, and `roles/iam.roleAdmin` to the orchestrator SA `secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com`.
- Create a project-scoped custom role `deployerMinimal` with minimal deploy permissions.
- Create a service account `deployer-sa@nexusshield-prod.iam.gserviceaccount.com` and bind the `deployerMinimal` role to it.
- Create a service account key and store it in Secret Manager as the secret `deployer-sa-key`.

Usage (run as Project Owner):

```bash
cd /home/akushnir/self-hosted-runner
bash infra/grant-orchestrator-roles.sh
```

After running: the orchestrator can activate the deployer SA from the GSM secret and proceed automatically. Optionally you can run the watcher which will wait for the secret and then run the orchestrator:

```bash
bash infra/wait-and-run-orchestrator.sh
```

If you prefer to manually grant roles instead of running the script, run the following (as Project Owner):

```bash
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member=serviceAccount:secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com \
  --role=roles/run.admin --quiet

gcloud projects add-iam-policy-binding nexusshield-prod \
  --member=serviceAccount:secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com \
  --role=roles/iam.serviceAccountAdmin --quiet

gcloud projects add-iam-policy-binding nexusshield-prod \
  --member=serviceAccount:secrets-orch-sa@nexusshield-prod.iam.gserviceaccount.com \
  --role=roles/iam.roleAdmin --quiet
```

Or run the full bootstrap script as Project Owner to create the deployer SA and key (same as `grant-orchestrator-roles.sh`):

```bash
bash infra/bootstrap-deployer-run.sh
```

Security notes:
- The script stores the deployer key in Secret Manager with automatic replication.
- The deployer key is created only if the deployer SA exists or is created by the script.
