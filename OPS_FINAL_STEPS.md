# Ops Handoff — Final Activation Steps

This file lists precise, copy-paste steps for an org/repo administrator to finish the FAANG CI/CD activation.

1) Connect Cloud Build ↔ GitHub (Org Admin)
   - Console: Cloud Build → Triggers → Connect repository → Install Cloud Build GitHub App for the organization.
   - Ensure OAuth app is installed on `kushin77/self-hosted-runner` and grant access to all branches.

2) Create Cloud Build triggers (if not already present)
   - Example commands (replace buckets/URIs):
     - `gcloud alpha builds triggers create github --name="policy-check-trigger" --repo-owner=kushin77 --repo-name=self-hosted-runner --branch-pattern="^main$" --build-config=cloudbuild.policy-check.yaml --project=nexusshield-prod --substitutions=_POLICY_BUCKET=gs://nexusshield-policy,_NOTIFY_EMAIL=ops@example.com`
     - `gcloud alpha builds triggers create github --name="direct-deploy-trigger" --repo-owner=kushin77 --repo-name=self-hosted-runner --branch-pattern="^main$" --build-config=cloudbuild.yaml --project=nexusshield-prod --substitutions=_SBOM_BUCKET=gs://nexusshield-sbom,_COSIGN_KMS_URI=projects/nexusshield-prod/locations/global/keyRings/KEYRING/cryptoKeys/COSIGN`

3) Verify triggers and add required status checks
   - `gcloud alpha builds triggers list --project=nexusshield-prod --format=json`
   - In GitHub: Settings → Branches → Protect `main` → Add required status checks matching the Cloud Build trigger status contexts (use the trigger names shown by Cloud Build).

4) Disable GitHub Actions (Repo Admin)
   - Web UI: Settings → Actions → Actions permissions → Disable or Restrict to `Allow local only` as desired.
   - API (example): `gh api -X PUT /repos/kushin77/self-hosted-runner/actions/permissions --raw-field enabled:=false` (requires admin token).

5) Create Cloud Build logs & SBOM buckets (if not created)
   - `gcloud storage buckets create gs://nexusshield-cloudbuild-logs --project=nexusshield-prod --location=us-central1 --uniform-bucket-level-access`
   - Grant Cloud Build SA: `gcloud projects add-iam-policy-binding nexusshield-prod --member=serviceAccount:PROJECT_NUMBER@cloudbuild.gserviceaccount.com --role=roles/storage.objectAdmin`

6) Validate locally / run smoke tests (Ops)
   - Run the circuit-breaker smoke test: `python3 backend/circuit_breaker.py` (already passes but reports `open` state when failures simulated).
   - Run E2E in an isolated virtualenv or CI runner (example):
     ```bash
     python3 -m venv .venv && . .venv/bin/activate
     python -m pip install -r requirements.txt pytest pytest-asyncio httpx
     pytest -q tests/e2e_test_framework.py::test_happy_path -k test_happy_path -s
     ```

7) Dry-run self-healing & audit
   - Run the script in DRY-RUN mode (override infra command behaviors):
     ```bash
     LOG_BUCKET=gs://nexusshield-prod-self-healing-logs DRY_RUN=1 bash -lc '\
       gcloud() { echo "[DRY_RUN] gcloud $*"; } \
       gsutil() { echo "[DRY_RUN] gsutil $*"; } \
       kubectl() { echo "[DRY_RUN] kubectl $*"; } \
       /home/akushnir/self-hosted-runner/scripts/self-healing/self-healing-infrastructure.sh'
     ```

8) Merge PR & enable enforcement
   - Once Cloud Build triggers appear and required status checks are visible, merge PR `faang-cicd-standards-milestone4` (PR #2961).
   - Confirm the `policy-check` trigger rejects PRs that modify `.github/workflows`.

9) Final audit
   - Verify audit JSONL uploaded to Object Lock bucket and confirm retention policy.
   - Notify on-call and schedule production activation window.

Contact: ops (ops@example.com) for assistance performing org-level actions.
