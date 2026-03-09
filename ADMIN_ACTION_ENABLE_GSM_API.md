# Admin Action Required: Enable GSM API (Secret Manager)

Action: Enable Secret Manager API on project `p4-platform`.

Command (GCP Admin):

```bash
gcloud services enable secretmanager.googleapis.com --project=p4-platform
```

Context:
- Attempted by `akushnir@bioenergystrategies.com` and failed with `PERMISSION_DENIED`.
- This is a 2-minute admin operation; once complete the provisioning system will promote GSM to primary and auto-provision the `STAGING_KUBECONFIG` secret.

Next steps for Admin:
1. Run the command above with a project admin account or service-account with `servicemanagement.services.enable` permission.
2. Verify with:

```bash
gcloud services list --project=p4-platform | grep secretmanager
```

3. After enabling, the system will auto-run provisioning scripts and generate kubeconfig.

Audit: This action was attempted and logged in `/tmp/gsm-enable.out` on the runner.
