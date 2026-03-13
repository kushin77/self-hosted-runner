PR Note: Cloud Build Triggers Creation Blocked

Summary
-------
Attempted to create Cloud Build GitHub-backed triggers for `policy-check` and `direct-deploy`, but the project has no Cloud Build GitHub connections configured. Trigger creation returns INVALID_ARGUMENT when attempted.

Cause
-----
- Cloud Build GitHub App / OAuth connection is not installed for the organization/repo.

Action Needed (Org Admin)
-------------------------
Please follow the steps in `OPS_FINAL_STEPS.md` to install/connect the Cloud Build GitHub App for `kushin77/self-hosted-runner`, then re-run the trigger creation commands.

Suggested PR comment (copy & paste):
```
Heads-up: I implemented FAANG CI/CD configs in branch `faang-cicd-standards-milestone4` (PR #2961).

I attempted to provision Cloud Build triggers, but the project has no Cloud Build ↔ GitHub connection (Cloud Build connections list is empty). An org admin must install/authorize the Cloud Build GitHub App for `kushin77` so I can create the triggers and validate required status checks.

Please see `/OPS_FINAL_STEPS.md` for exact commands and the remaining manual steps.
```

Files added/changed in this branch:
- `cloudbuild.policy-check.yaml`
- `cloudbuild.openapi-validation.yaml`
- `cloudbuild.yaml` (deploy)
- `backend/circuit_breaker.py`
- `scripts/self-healing/self-healing-infrastructure.sh`
- `tests/e2e_test_framework.py`
- `OPS_FINAL_STEPS.md` (ops handoff)

Next steps I can take once the Cloud Build GitHub App is connected:
1. Create the GitHub-backed Cloud Build triggers and verify they're active.
2. Add the new triggers as required status checks in branch protection.
3. Merge PR #2961 and confirm enforcement.

Contact: ops@example.com if you want me to proceed with admin-side steps once they're completed.
