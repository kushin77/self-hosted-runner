# Cloud Build ↔ GitHub OAuth Connection — Admin Instructions

One-time GCP org/project admin action to authorize Cloud Build access to this GitHub repository.

Steps (UI):
1. Go to Cloud Console → Cloud Build → Repositories → Connect Repository
2. Choose GitHub and follow the OAuth flow to authorize the Google Cloud Build GitHub App for repository `kushin77/self-hosted-runner`.
3. Confirm the connection appears for region `us-central1` and project `nexusshield-prod`.
4. After authorization, run the automation script to create triggers:

```bash
# On a machine with gcloud configured for project nexusshield-prod
export PROJECT=nexusshield-prod
bash scripts/ops/create_cloudbuild_triggers.sh
```

5. Then configure branch protection (requires GitHub repo admin):

```bash
# Requires GH CLI logged in as a repo admin
bash scripts/ops/configure_branch_protection.sh
```

If you prefer a UI walkthrough, the Cloud Console shows the connected repositories list after step 2.
