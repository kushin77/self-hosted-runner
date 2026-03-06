#000 — Runner debug & migration plan

Status: Open
Owner: @kushin77 (adjust as needed)

Summary
-------
Self-hosted group runner pipelines are blocked by failing jobs in earlier stages. This issue tracks the immediate isolation test, diagnostics collection, and recommended migration to ephemeral, immutable Kubernetes-based runners.

Actions taken
-------------
- Added a pre-flight isolation job `YAMLtest-sovereign-runner` to `.gitlab-ci.yml` to validate runner pickup.
- Added `scripts/ci/collect_runner_info.sh` to gather runner version, `/etc/gitlab-runner/config.toml`, journal logs, and Docker info.
- Added Helm values template and helper scripts for Kubernetes executor under `infra/gitlab-runner/` and `scripts/ci/`.

Next steps (short-term)
----------------------
1. Replace the placeholder runner tag in `.gitlab-ci.yml` with the exact group-runner tag for testing locally.
2. On the runner host, run `scripts/ci/collect_runner_info.sh` and attach the redacted archive to this issue.
3. Paste the failing job's last 20–30 lines here (red error output).
4. Paste the `[[runners]]` section from `/etc/gitlab-runner/config.toml` (redact tokens/URLs if necessary).
5. (Local-first) Render `infra/gitlab-runner/values.generated.yaml` from the template and install to a test k3s cluster using `scripts/ci/install_runner_k8s.sh`.

Recommended mid-term migration (immutable, sovereign, ephemeral)
---------------------------------------------------------------
- Deploy GitLab Runner using the official Helm chart to the k3s/Kubernetes cluster.
- Register at group level with Kubernetes executor so each job runs in an ephemeral pod.
- Configure Vault integration using GitLab's Vault secrets feature (OIDC/JWT) to avoid static secrets.
- Add monitoring via GitLab CI metrics → Prometheus + Grafana (idempotent provisioning via Terraform).

Acceptance criteria
-------------------
- The `YAMLtest-sovereign-runner` job runs and passes on the new k8s-backed group runner.
- Failing-job root cause identified and fixed so pipelines reach subsequent stages.
- A migration plan (helm values + registration steps) is created and rehearsed in a non-prod group.

Notes
-----
Do not paste any secrets, private keys, or unredacted tokens in this issue. Use the helper script and redact before sharing.
