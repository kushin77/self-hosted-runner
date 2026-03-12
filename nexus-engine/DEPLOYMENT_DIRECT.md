# Direct Deployment Runbook

Purpose: provide direct, operator-run deployment steps (no GitHub Actions, no PR-based releases).

Prerequisites
- Operator machine with Docker, Go toolchain, and access to secrets via Vault or GCP Secret Manager.
- Credentials provisioned via GSM (GCP Secret Manager), Vault, or KMS only. No secrets in repo.

Quick steps
1. On operator host, fetch secrets into environment or ensure `docker`/`gcloud` is authenticated.
2. From repository root, run:

```bash
cd nexus-engine
IMAGE=gcr.io/my-project/nexus-ingestion TAG=2026-03-12 ./scripts/deploy_direct.sh
```

3. After image push, deploy using your infra tooling (GKE/Cloud Run/Terraform). Example (Cloud Run):

```bash
gcloud run deploy nexus-ingestion --image "$IMAGE:$TAG" --region us-central1 --platform managed
```

Security notes
- Do not store secrets in files. Use Vault or GSM and inject ephemeral credentials into the operator environment.
- All credential operations should be audited and use short TTLs where possible.

Rollback
- Use your container registry to redeploy previous image tag.

Contact
- For assistance, post Day 1 outputs to issue #2688 and tag the operator on-call.
