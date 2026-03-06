#103 — Trigger GSM CI Deploy Job (deploy:sovereign-runner-gsm)

Status: Open
Owner: Platform/CI operator

Purpose
-------
This issue provides step-by-step instructions to trigger the protected manual GitLab CI job `deploy:sovereign-runner-gsm`, which will fetch kubeconfig and registration token from GCP Secret Manager, then perform a hands-off Helm-based GitLab Runner installation with SealedSecrets support.

Prerequisites
--------------
- Completed issue #102 (GSM secrets setup): all four protected GitLab CI variables are set
- Maintainer or Owner access to the target GitLab group/project
- Knowledge of the current branch (typically `main`)

Step 1: Trigger the Pipeline
-----------------------------
In GitLab UI:
1. Navigate to Pipelines (CI/CD → Pipelines)
2. Click "Run pipeline"
3. Select branch: `main`
4. Click "Create pipeline"

Step 2: Start the Manual Deploy Job
-----------------------------------
Once the pipeline is created:
1. View the pipeline details
2. Locate the manual job: `deploy:sovereign-runner-gsm`
3. Click the play icon (▶) to start the job

Alternatively, if you have a GitLab API token and project id, trigger via CLI:
```bash
GITLAB_API_TOKEN=<token> \
GITLAB_URL=https://gitlab.com \
PROJECT_ID=<project_id> \
  ./scripts/ci/trigger_yamltest_pipeline.sh main
```

Then in the GitLab UI, start the manual job.

Step 3: Monitor Job Logs
------------------------
Watch the job logs in real-time:
1. Click the job name to open the job detail page
2. Scroll through the "logs" section and observe:
   - GCP authentication: "Activating service account..."
   - Secret fetch: "Fetching kubeconfig secret: ..." and "Fetching registration token secret: ..."
   - Secret apply: "SealedSecret generated" or "Secret created"
   - Helm install: "Helm install/upgrade gitlab-runner ..."
   - Pod readiness: "Waiting for pods..." and "All pods ready"

Step 4: Verify Deployment Success
---------------------------------
Once the job is complete ("Passed" status shown), verify:
```bash
kubectl -n gitlab-runner get pods -o wide
kubectl -n gitlab-runner logs -l app=gitlab-runner --tail=100
kubectl -n gitlab-runner get secret gitlab-runner-regtoken
```

Troubleshooting
---------------
- **Job status: Failed** — Check logs for error messages. Common issues:
  - GCP authentication failed: verify `GCP_SA_KEY` and service account permissions.
  - Secret not found: check `KUBECONFIG_SECRET_NAME` and `REGTOKEN_SECRET_NAME` values match actual GSM secret names.
  - Helm install failed: check Kubernetes connectivity (kubeconfig parsing).
- **Pod stuck "Pending"**: could indicate image pull policy or resource constraints; check events:
  ```bash
  kubectl -n gitlab-runner describe pod <pod-name>
  ```

Post-Deploy
-----------
Once the job completes successfully, proceed to issue #104 to validate the runner and trigger test jobs.

Notes
-----
- The entire process is non-interactive after job start; logs show all actions taken.
- Secrets are fetched at job runtime from GSM and never committed to Git.
- If the job is re-run, it will perform an idempotent Helm upgrade (not a fresh install).
