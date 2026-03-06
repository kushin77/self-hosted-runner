#104 — Post-Deploy Validation & YAMLtest Runner Job

Status: Open
Owner: Platform/CI operator

Purpose
-------
After the `deploy:sovereign-runner-gsm` CI job completes successfully, this issue guides validation of the newly deployed Kubernetes-based GitLab Runner and execution of the pre-flight `YAMLtest-sovereign-runner` job to confirm the runner environment is production-ready.

Prerequisites
--------------
- Issue #103 completed: `deploy:sovereign-runner-gsm` job passed
- Kubernetes cluster reachable and runner pods are in Running state
- Branch: `main` or feature branch with the pre-flight test job enabled

Step 1: Verify Runner Pods
--------------------------
From a terminal with kubectl access:
```bash
kubectl -n gitlab-runner get pods -L app,status
kubectl -n gitlab-runner logs -l app=gitlab-runner --tail=200 | head -100
```

Expected output:
- Pods named `gitlab-runner-<hash>` and/or `gitlab-runner-0` in `Running` state
- Logs show successful registration and ready to accept jobs

Step 2: Verify Runner Tag Registration
--------------------------------------
Check that the runner is registered with the correct tags in GitLab:
1. GitLab UI: Admin → Runners
2. Look for the new runner with tags: `k8s-runner, sovereign, ephemeral, immutable`
3. Verify it shows "Online" status

Step 3: Trigger the YAMLtest-sovereign-runner Pipeline
------------------------------------------------------
The repository includes a pre-flight test job `YAMLtest-sovereign-runner` which confirms syntax and basic cluster connectivity.

Option A: Trigger via UI
1. Go to Pipelines → Run pipeline → branch `main`
2. Job `YAMLtest-sovereign-runner` should appear in the `.pre` stage
3. If it does not run automatically, click the play icon to start it

Option B: Trigger via CLI (requires GITLAB_API_TOKEN and PROJECT_ID)
```bash
GITLAB_API_TOKEN=<token> \
PROJECT_ID=<project_id> \
GITLAB_URL=https://gitlab.com \
  ./scripts/ci/trigger_yamltest_pipeline.sh main
```

Step 4: Monitor YAML Test Job
-----------------------------
Once the pipeline is running, watch the `YAMLtest-sovereign-runner` job:
```
Pipeline → Jobs → YAMLtest-sovereign-runner → Logs
```

The job should:
1. Pull an alpine image
2. Run kubectl checks (list namespaces, get runner pods, check cluster version)
3. Output: "✓ All validation checks passed"
4. Status: Passed

Step 5: Success Criteria
------------------------
- [ ] All runner pods are in `Running` state
- [ ] Runner is registered in GitLab with correct tags
- [ ] Runner status shows "Online"
- [ ] `YAMLtest-sovereign-runner` job passes
- [ ] No errors in runner logs related to image pulls or cluster connectivity

Step 6: Next Steps
------------------
If all validation checks pass:
- Runner environment is confirmed production-ready
- Proceed to issue #105 to plan runner migration and legacy runner decommissioning

If validation fails:
- Check runner logs for errors: `kubectl -n gitlab-runner logs -l app=gitlab-runner --timestamps=true | tail -50`
- Verify kubeconfig and network connectivity
- Re-run the validation in issue #103 or contact platform team

Troubleshooting
---------------
- **Pod in CrashLoopBackOff or NotReady**: check pod events and logs for registration errors
  ```bash
  kubectl -n gitlab-runner describe pod <pod-name>
  kubectl -n gitlab-runner logs <pod-name> --previous
  ```
- **Runner not appearing in GitLab UI**: check that registration token was properly injected; re-run the deploy job
- **YAMLtest-sovereign-runner job pending/not running**: runner may not be online yet; wait 30-60s and check logs

Notes
-----
- The validation job is idempotent and can be re-run as needed
- Runner pods are ephemeral; each CI job creates a new pod
- If runner is decommissioned, jobs will be queued until a new runner comes online
