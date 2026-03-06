#000 — Runner debug & migration plan

Status: In Progress
Owner: @kushin77 (adjust as needed)

Summary
-------
Self-hosted group runner pipelines are blocked by failing jobs in earlier stages. This issue tracks the immediate isolation test, diagnostics collection, and recommended migration to ephemeral, immutable Kubernetes-based runners.

Actions taken / Done
-------------
- Added a pre-flight isolation job `YAMLtest-sovereign-runner` to `.gitlab-ci.yml` to validate runner pickup.
- Added `scripts/ci/collect_runner_info.sh` to gather runner version, `/etc/gitlab-runner/config.toml`, journal logs, and Docker info.
- Added Helm values template and helper scripts for Kubernetes executor under `infra/gitlab-runner/` and `scripts/ci/`.

- Created local-only branch and committed migration artifacts (local, not pushed).
- Added `infra/gitlab-runner/values.yaml.template`, `scripts/ci/generate_values_for_runner.sh`, and `scripts/ci/install_runner_k8s.sh`.

Checklist
---------
- [x] Add pre-stage `YAMLtest-sovereign-runner` job to `.gitlab-ci.yml` (local)
- [x] Add diagnostics helper `scripts/ci/collect_runner_info.sh`
- [x] Add Helm values template and install helpers (local)
- [x] Generated sample `infra/gitlab-runner/values.generated.yaml` (dry-run)
- [ ] Run diagnostics on runner host and attach redacted archive
- [x] Render values with real token and install to test k3s/K8s cluster
- [ ] Validate `YAMLtest-sovereign-runner` passes on new runner - ready for user
- [ ] Migrate group runner registration to k8s-backed runner - ready for user
- [ ] Decommission legacy VM-based runners (after rollback window)

Next steps (short-term)
----------------------
1. The placeholder runner tag in `.gitlab-ci.yml` has been updated to "k8s-runner" for the new runner.
2. On the runner host, run `scripts/ci/collect_runner_info.sh` and attach the redacted archive to this issue.
3. Paste the failing job's last 20–30 lines here (red error output).
4. Paste the `[[runners]]` section from `/etc/gitlab-runner/config.toml` (redact tokens/URLs if necessary).
5. (Local-first) Render `infra/gitlab-runner/values.generated.yaml` from the template and install to a test k3s cluster using `scripts/ci/install_runner_k8s.sh`. - DONE
6. Trigger a pipeline to run the `YAMLtest-sovereign-runner` job and verify it passes on the new k8s runner.
7. If successful, migrate the group runner registration fully and decommission the legacy runner.

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
