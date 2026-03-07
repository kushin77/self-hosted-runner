Support Request: dr-smoke-test failing 6 consecutive runs

Repository: kushin77/self-hosted-runner
Date: 2026-03-07

Summary:
- The `dr-smoke-test.yml` workflow has failed 6 consecutive runs (IDs listed below).
- Failure appears at step "Compile DR readiness summary" with `GCP_STATUS="invalid_structure"` while `DOCKER_STATUS="docker_ok"`.
- Likely root cause: malformed or incorrectly-ingested `GCP_SERVICE_ACCOUNT_KEY` secret (missing `"type": "service_account"` field) or secrets being altered/masked by the runner environment.

Recent failing runs (newest first):
- https://github.com/kushin77/self-hosted-runner/actions/runs/22806651875  (2026-03-07T20:29:35Z)
- https://github.com/kushin77/self-hosted-runner/actions/runs/22806383501  (2026-03-07T20:12:34Z)
- https://github.com/kushin77/self-hosted-runner/actions/runs/22806292085  (2026-03-07T20:07:05Z)
- https://github.com/kushin77/self-hosted-runner/actions/runs/22805811061  (2026-03-07T19:37:14Z)
- https://github.com/kushin77/self-hosted-runner/actions/runs/22805662414  (2026-03-07T19:27:51Z)
- https://github.com/kushin77/self-hosted-runner/actions/runs/22805200585  (2026-03-07T18:59:32Z)

Artifacts and logs available on operator host:
- /tmp/artifacts/dr-22806651875/log_tail.txt
- /tmp/artifacts/verify-22806651593/verify-diagnostics-22806651593/tmp/verify-diagnostics.txt

Actions taken so far by automation:
- Background monitor downloaded artifacts to `/tmp/artifacts/`.
- Escalation issue opened in repo: https://github.com/kushin77/self-hosted-runner/issues/1312
- Activation issue updated; remediation issue updated with run links and artifact locations.

Requested investigation (platform support):
1. Confirm GitHub Actions runner environment permissions and network access for any GCP endpoints required by `dr-smoke-test`.
2. Inspect how repository secrets are presented to the workflow runner; verify there is no masking/truncation or newline/quote mangling of `GCP_SERVICE_ACCOUNT_KEY`.
3. If secrets are verified OK, provide guidance on debugging the runner's environment (shell env, file system, masking behavior) or request agent to run a capture script on the runner.
4. If needed, request a temporary debug session or share steps to collect further logs. The operator can provide additional artifacts from `/tmp/artifacts/` on request.

Contact:
- Operator: @akushnir
- Escalation issue: https://github.com/kushin77/self-hosted-runner/issues/1312

Notes:
- We prefer not to share secrets in the support request; the operator is ready to provide sanitized artifacts on request.
