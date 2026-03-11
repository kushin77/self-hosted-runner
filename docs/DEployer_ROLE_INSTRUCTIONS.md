# Deployer Role Apply Instructions

This PR adds a minimal custom IAM role definition for a deployer service account required to run the automated `prevent-releases` deployment.

How to apply (project owner):

```bash
PROJECT=nexusshield-prod
ROLE_ID=deployerMinimal
# Create custom role
gcloud iam roles create ${ROLE_ID} --project=${PROJECT} --file=iam/deployer-role.json

# Create deployer service account
gcloud iam service-accounts create deployer-sa --project=${PROJECT} --display-name="Deployer SA"

# Bind the custom role to the SA
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member="serviceAccount:deployer-sa@${PROJECT}.iam.gserviceaccount.com" \
  --role="projects/${PROJECT}/roles/${ROLE_ID}"

# Create key and upload it to the runner at /tmp/deployer-sa-key.json (owner-run)
gcloud iam service-accounts keys create /tmp/deployer-sa-key.json --iam-account=deployer-sa@${PROJECT}.iam.gserviceaccount.com
```

After uploading the key to the runner (or running locally):

```bash
# On runner
gcloud auth activate-service-account --key-file=/tmp/deployer-sa-key.json
gcloud config set project nexusshield-prod
bash infra/complete-deploy-prevent-releases.sh
```

Notes:
- This custom role is intentionally narrow to satisfy least-privilege.
- If you prefer granting roles to an existing SA instead, use the commands in issue #2624.
