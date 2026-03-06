#100 — Runner Migration Plan (k8s executor, local-first)

Status: Ready for protected GitLab CI deploy
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
1. Render `infra/gitlab-runner/values.generated.example.yaml` from template (no real tokens committed). - DONE
2. Install via protected GitLab CI manual job (recommended) using `.gitlab/ci-includes/runner-deploy.gitlab-ci.yml` — requires `KUBECONFIG_BASE64` and `REG_TOKEN` as protected CI variables. - READY
3. Verify `gitlab-runner` pods and logs; ensure metrics endpoint is reachable. - READY (once CI job completes)
4. Update `.gitlab-ci.yml` locally to use the runner tag produced by the k8s runner. - DONE
5. Trigger pipeline (or create temporary local MR) to run `YAMLtest-sovereign-runner`. - WAITING
6. If green, update GitLab group runner registration (swap tokens/enable new runner) and retire old runner. - PENDING

Blocking status:
- If using local cluster: kubeconfig `production-context` currently points to unreachable API server (192.168.168.42:6443) — please restore or provide alternate kubeconfig.
- For CI deploy: set `KUBECONFIG_BASE64` and `REG_TOKEN` as protected variables in GitLab (group/project) to run the manual deploy job.

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
