# Request: GCP Workload Identity + Repo Secrets for Deploy SSH Key

Related PR: #708
Related Issue: #707

Summary
---
We updated the `deploy-rotation-staging` GitHub Actions workflow to fetch the deploy SSH private key from GCP Secret Manager via OIDC (Workload Identity). Before the workflow can fetch secrets, ops must perform the following steps.

Required steps (ops)
---
1. Create a Workload Identity Pool provider bound to this GitHub repository.
   - Example resource name:
     `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL/providers/PROVIDER`
   - Follow: https://cloud.google.com/iam/docs/workload-identity-federation

2. Create or choose a service account to be used by the workflow (e.g., `ci-deployer@PROJECT.iam.gserviceaccount.com`).

3. Grant the Workload Identity provider permission to impersonate the service account.
   - Use this command (replace placeholders):
     ```bash
     gcloud iam service-accounts add-iam-policy-binding ci-deployer@PROJECT.iam.gserviceaccount.com \
       --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL/attribute.repository/kushin77/self-hosted-runner" \
       --role="roles/iam.workloadIdentityUser"
     ```

4. Grant the service account permission to access the secret in Secret Manager and to create access tokens (if needed):
   - Secret access:
     ```bash
     gcloud secrets add-iam-policy-binding STAGING_SSH_KEY \
       --member="serviceAccount:ci-deployer@PROJECT.iam.gserviceaccount.com" \
       --role="roles/secretmanager.secretAccessor"
     ```

5. (Optional) Grant `roles/iam.serviceAccountTokenCreator` if the workflow needs to mint tokens for other APIs.

6. Add the following repository secrets in GitHub (Repository Settings -> Secrets -> Actions):
   - `GCP_WORKLOAD_IDENTITY_PROVIDER`: the full provider resource name from step 1.
   - `GCP_SERVICE_ACCOUNT`: the service account email from step 2.

7. In Secret Manager, ensure the SSH private key is stored as a secret named e.g. `STAGING_SSH_KEY`.
   - The workflow input `gsm_secret_name` should be set to the Secret Manager resource path, e.g. `projects/PROJECT_NUMBER/secrets/STAGING_SSH_KEY/versions/latest`.

8. Merge PR #708 and then dispatch the `deploy-rotation-staging` workflow with inputs:
   - `inventory_file`: `ansible/inventory/staging`
   - `gsm_provider`: `gcp`
   - `gsm_secret_name`: `projects/PROJECT_NUMBER/secrets/STAGING_SSH_KEY/versions/latest`
   - `ansible_user`: `deploy` (or appropriate user)
   - `dry_run`: `false`

Verification
---
- After dispatch, the workflow should fetch the SSH key and write it to `/tmp/deploy_id_rsa` and pass it to `ansible-playbook`.
- I will monitor the workflow run, verify the deployment, and update/close related issues (#707, PR #708) once successful.

If you prefer an alternative GSM (Vault/AWS), reply and I will add equivalent workflow steps.
