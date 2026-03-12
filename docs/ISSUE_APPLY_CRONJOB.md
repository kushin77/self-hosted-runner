Apply milestone-organizer CronJob to cluster (urgent)

Summary
-------
The `milestone-organizer` CronJob manifest was merged into `main` via PR #2653 but the cluster API was unreachable from the automation host. Please apply the manifest from a node with cluster access.

PR / Branch
-----------
- PR: https://github.com/kushin77/self-hosted-runner/pull/2653
- Branch: `deploy/milestone-organizer-cronjob`

Manifest
--------
- `k8s/milestone-organizer-cronjob.yaml`

Operator steps (recommended)
---------------------------
1. Checkout branch and confirm manifest:

```bash
git fetch origin
git checkout deploy/milestone-organizer-cronjob
cat k8s/milestone-organizer-cronjob.yaml
```

2. Apply the manifest (idempotent):

```bash
# from a node with cluster access and correct kubeconfig
kubectl apply --validate=false -f k8s/milestone-organizer-cronjob.yaml
# verify
kubectl -n ops get cronjob milestone-organizer
kubectl -n ops get sa milestone-organizer-sa -o yaml
```

3. If API is flaky, use retry helper shipped in repo:

```bash
bash scripts/ops/retry-kubectl-apply.sh ops
```

4. After apply, post success comment to PR #2653 and close this issue.

Notes / Safety
--------------
- This manifest is ephemeral & idempotent; `kubectl apply` is safe to re-run.
- Credentials are designed to use GSM/Vault/KMS (manifest contains placeholders). Confirm secret injection mechanism before production use.
- No GitHub Actions or PR-release workflows were used — direct deployment pattern per policy.

Audit logs
----------
- Audit entry created: `logs/multi-cloud-audit/operator-apply-request-*.jsonl`
- PR watcher logs: `logs/pr-2653-watch-*.log`

Contact
-------
Assign to `akushnir` (lead engineer) or on-call platform/operator.
