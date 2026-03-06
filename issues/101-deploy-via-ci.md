#101 — Deploy GitLab Runner via protected GitLab CI job (Checklist)

Status: Open
Owner: Platform/CI operator

Purpose
-------
This issue guides operators through performing the hands-off GitLab Runner deployment using the protected manual CI job `deploy:sovereign-runner` included in the repository. It ensures secrets remain guarded in GitLab and the deployment is idempotent and observable.

Checklist
---------
- [ ] Ensure you have Maintainer access to the target GitLab group/project.
- [ ] Generate or obtain a short-lived `REG_TOKEN` for group-level runner registration.
- [ ] On a secure machine with cluster access, base64-encode the target kubeconfig:

```bash
base64 -w0 ~/.kube/config > kubeconfig.b64
# copy the contents securely for the GitLab variable
```

- [ ] In GitLab UI (Group/Project > Settings > CI/CD > Variables), add two protected, masked variables:
  - `KUBECONFIG_BASE64` = contents of `kubeconfig.b64`
  - `REG_TOKEN` = registration token (short-lived)

- [ ] Open Pipelines → Run pipeline → select `main` and start a pipeline.
- [ ] In the pipeline view, locate and click the manual job `deploy:sovereign-runner` to start the deploy.
- [ ] Monitor the job logs for SealedSecret creation (or Secret), Helm install, and pod readiness.

Verification
------------
- After job completes, verify runner pods:

```bash
kubectl -n gitlab-runner get pods
kubectl -n gitlab-runner logs -l app=gitlab-runner --tail=200
```

- Trigger validation pipeline/job (optional):

```bash
# From local secure machine with API token:
GITLAB_API_TOKEN=<token> PROJECT_ID=<id> ./scripts/ci/trigger_yamltest_pipeline.sh main
```

Post-deploy
-----------
- If the `YAMLtest-sovereign-runner` job passes, update the migration issue to mark completion and schedule decommissioning of legacy runners with appropriate rollback window.

Notes
-----
- Do not paste tokens in issue comments; use GitLab protected variables only.
- If CI job fails due to cluster reachability, follow `issues/999-cluster-outage.md`.
