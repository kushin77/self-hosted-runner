#102 — GCP Secret Manager (GSM) Setup for CI Deploy

Status: Open
Owner: Platform/CI operator

Purpose
-------
This issue documents how to set up GCP Secret Manager secrets and configure GitLab CI protected variables to enable the hands-off automated runner deployment via the `deploy:sovereign-runner-gsm` CI job.

Prerequisites
--------------
- GCP project with Secret Manager API enabled
- Service account with at least `secretmanager.secretAccessor` role
- `gcloud` CLI authenticated and able to list/access secrets

Secrets to Create in GCP Secret Manager
---------------------------------------
Create four secrets in your GCP project (project id: `gcp-eiq`):

1. **kubeconfig secret**
   - Name: `kubeconfig-secret` (or your chosen `KUBECONFIG_SECRET_NAME`)
   - Value: base64-encoded kubeconfig for the target Kubernetes cluster
   ```bash
   base64 -w0 ~/.kube/config | gcloud secrets versions add kubeconfig-secret --data-file=- --project=gcp-eiq
   ```

2. **registration token secret**
   - Name: `gitlab-runner-regtoken` (or your chosen `REGTOKEN_SECRET_NAME`)
   - Value: the short-lived GitLab Runner registration token (from GitLab Admin > Runners > New group runner)
   ```bash
   echo -n "<REG_TOKEN>" | gcloud secrets versions add gitlab-runner-regtoken --data-file=- --project=gcp-eiq
   ```

3. **service account key secret** (optional but recommended)
   - Name: `gcp-sa-key` (or your chosen `GCP_SA_KEY` secret name)
   - Value: base64-encoded JSON of a service account key (grant Secret Manager access)
   ```bash
   base64 -w0 /path/to/sa-key.json | gcloud secrets versions add gcp-sa-key --data-file=- --project=gcp-eiq
   ```

Checklist
---------
- [ ] GCP project id: `gcp-eiq` confirmed and accessible via `gcloud`
- [ ] Service account created with `secretmanager.secretAccessor` role
- [ ] Kubeconfig secret created (name: `kubeconfig-secret`)
- [ ] Registration token secret created (name: `gitlab-runner-regtoken`)
- [ ] Service account key JSON base64-encoded and ready for GitLab CI variable
- [ ] In GitLab UI (Group/Project → Settings → CI/CD → Variables), add four protected, masked variables:
  - `GCP_PROJECT` = `gcp-eiq`
  - `GCP_SA_KEY` = base64-encoded service account JSON key
  - `KUBECONFIG_SECRET_NAME` = `kubeconfig-secret`
  - `REGTOKEN_SECRET_NAME` = `gitlab-runner-regtoken`

Verification
------------
Once secrets are created, verify gcloud can read them:
```bash
gcloud secrets versions access latest --secret=kubeconfig-secret --project=gcp-eiq | head -c50
gcloud secrets versions access latest --secret=gitlab-runner-regtoken --project=gcp-eiq
```

Post-verification
-----------------
Once all secrets are in place and GitLab CI variables are set (protected, masked), you are ready to proceed to issue #103 to trigger the CI deploy job.

Notes
-----
- Keep the service account key secure; rotating keys regularly is a best practice.
- GitLab protected variables are masked in CI logs to prevent accidental exposure.
- GitLab masked variables are redacted from job logs.
