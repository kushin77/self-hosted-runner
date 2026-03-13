# Cloud Build GitHub Connection — Manual Steps

This file documents the manual steps required when Cloud Build cannot connect to GitHub programmatically.

Why this is needed
- The Cloud Build GitHub App installation/authorization is an OAuth-style flow that normally requires interactive approval in the GCP Console. Automated, non-interactive creation often fails with "No GitHub repositories connected to Cloud Build." The setup script will detect this and exit with guidance.

Quick admin steps
1. Open the Cloud Build repositories page in the GCP Console for the target project (replace PROJECT_ID as needed):
   https://console.cloud.google.com/cloud-build/repositories?project=PROJECT_ID
2. Click "Connect Repository" → choose "GitHub" → follow the prompt to authorize the Cloud Build GitHub App.
3. Select the repository: `kushin77/self-hosted-runner` (or the correct owner/repo for your deployment).
4. After install/authorization completes, re-run the helper script on the repo root:

```bash
# from repository root
bash scripts/ops/setup-cloud-build-trigger.sh --project nexusshield-prod
```

Optional: create the connection via CLI (advanced)
- If you prefer to create a connection from the CLI rather than the console, obtain the GitHub App installation ID from the Cloud Console after authorizing the app, then run:

```bash
gcloud alpha builds connections create --region=global github \
  --name=github-connection \
  --project=nexusshield-prod \
  --installation-id=INSTALLATION_ID
```

Notes
- The `INSTALLATION_ID` is displayed in the Cloud Build → Repositories page or via the Console's connection details after you approve the GitHub App.
- Once the connection exists, the `setup-cloud-build-trigger.sh` script will create the trigger and assign the Cloud Build SA roles.
- If you'd like, provide me the installation ID (or confirm you completed the console step) and I will re-run the setup script to finish trigger creation.

Contact
- If you need assistance performing the console install, reply here and I can prepare a one-click checklist you can copy into the console session.
