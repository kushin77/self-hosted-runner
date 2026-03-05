Title: Request: Inject Cloud Provider Credentials for Automated Tests

Description:
We need Ops to inject cloud provider credentials into the repository (or the web portal) so the automated cloud provider verification tests can run.

Checklist (please complete):
- [ ] AWS credentials
  - [ ] Add `AWS_ACCESS_KEY_ID` (repo secret)
  - [ ] Add `AWS_SECRET_ACCESS_KEY` (repo secret)
  - [ ] Add `AWS_REGION` (repo secret)
- [ ] GCP credentials
  - [ ] Add `GCP_SA_KEY` (service account JSON) as repo secret (raw JSON or base64)
  - [ ] Add `GCP_PROJECT` (repo secret)
- [ ] Azure credentials
  - [ ] Add `AZURE_CREDENTIALS` (service principal JSON containing `clientId`, `clientSecret`, `tenantId`, `subscriptionId`) as repo secret
- [ ] Confirm cost approval for running cloud tests in staging
- [ ] Reply on this issue when secrets are set and ready for test run

Portal/local option:
- If secrets cannot be added to repo, upload `tests/cloud-creds.env` via portal (owner-only perms). Use `tests/cloud-creds.env.example` as template.

How to validate (Ops):
1. Add required secrets to repository (Settings → Secrets and variables → Actions).
2. Optionally set `GCP_SA_KEY` as base64-encoded JSON if portal requires it.
3. Post back here with confirmation and any notes about scopes/regions used.

Automation notes for QA:
- After secrets are injected, the CI workflow `.github/workflows/cloud-tests.yml` can be manually dispatched or will run on push to `main`.
- Alternatively, the helper `tests/prepare-creds.sh` consumes environment secrets and writes `tests/cloud-creds.env` and credential files.

Assignees: ops-team, devops-platform
Labels: urgent, ops-action-required, testing

Created: 2026-03-05