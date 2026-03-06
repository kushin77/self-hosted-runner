#100 — Runner Migration Plan (k8s executor, local-first)

Status: In Progress
Owner: @kushin77

Summary
-------
Deploy GitLab Runner as an ephemeral, Kubernetes-executor-backed group runner to ensure immutable, sovereign, ephemeral, and idempotent CI jobs.

Goals
-----
- Each CI job runs in a disposable Kubernetes pod.
- No long-lived build hosts or static secrets on disk.
- Full automation: install via Helm, secrets via sealed/ExternalSecrets, registration token injected at install.

Steps (local-first)
-------------------
1. Render `infra/gitlab-runner/values.generated.example.yaml` from template (no real tokens committed).
2. Install into test k3s/K8s cluster with `scripts/ci/install_runner_k8s.sh`.
3. Verify `gitlab-runner` pods and logs; ensure metrics endpoint is reachable.
4. Update `.gitlab-ci.yml` locally to use the runner tag produced by the k8s runner.
5. Trigger pipeline (or create temporary local MR) to run `YAMLtest-sovereign-runner`.
6. If green, update GitLab group runner registration (swap tokens/enable new runner) and retire old runner.

Acceptance criteria
-------------------
- `YAMLtest-sovereign-runner` passes on the new runner.
- Jobs proceed to later stages without early-stage failure due to runner environment.
- No static secrets committed; registration tokens stored in sealed secrets or provided at install-time.

Risks & Rollback
----------------
- If jobs fail due to environment, rollback by disabling new runner in GitLab and re-enabling legacy runner.

Artifacts
---------
- `infra/gitlab-runner/values.yaml.template`
- `scripts/ci/generate_values_for_runner.sh`
- `scripts/ci/install_runner_k8s.sh`
