**Runner Migration — Kubernetes Executor (Ephemeral/Immutable)**

Goal
----
Move group-level runners from self-hosted VMs to Kubernetes executor so each job runs in an ephemeral pod. This enforces immutability, sovereignty, and idempotent automation.

Quick checklist (local-first)
----------------------------
- Generate a values file locally using `scripts/ci/generate_values_for_runner.sh` with a registration token scoped to the GitLab group.
- Install the chart into a target k3s/K8s cluster with `scripts/ci/install_runner_k8s.sh` (namespace defaults to `gitlab-runner`).
- Verify pods are running and check `gitlab-runner` logs.
- Test with `YAMLtest-sovereign-runner` after updating `.gitlab-ci.yml` tag to the runner's tags.

Security & Vault notes
----------------------
- Prefer GitLab's Vault integration (JWT/OIDC) to avoid static tokens where possible.
- If Vault is required for job secrets, configure Kubernetes to allow runner pods to fetch secrets at job runtime (service account + projected tokens).

Monitoring & Observability
--------------------------
- Expose runner metrics via Prometheus (chart includes metrics exporter). Configure Prometheus scrape target and dashboards in Grafana.

Acceptance criteria
-------------------
- `YAMLtest-sovereign-runner` passes on the new k8s-backed group runner.
- Jobs that previously failed due to runner environment now progress to later stages.
- No static secrets left on disk; registration tokens are stored in sealed secrets or injected at install time.

Rollback
--------
- If issues are detected, scale down/remove the k8s runner release and re-enable the original group runner in GitLab settings until fix is applied.
