---
title: "Provide on-prem SSH key or enable passwordless sudo for `akushnir`"
labels: [ops, blocker]
---

Summary
-------

During automated post-deploy verification for `canonical-secrets-api` on host `192.168.168.42` the verification run completed but several checks could not be fully validated because the runner lacks passwordless `sudo` on the remote host and the on-prem SSH private key is not available from the configured secret backends.

Evidence
--------

- Verifier output: `/tmp/deployment_verification_1773251208.txt`
- Validation report: `/tmp/post_deploy_validation_1773251207.jsonl`

Issue
-----

To complete fully automated, hands-off verification (immutable, ephemeral, idempotent), please do one of the following:

1. Store the on-prem SSH private key (PEM/ED25519) in Google Secret Manager as secret name `onprem_ssh_key`. The automation will fetch it at runtime and perform the remaining steps (copy env, enable/start service, capture logs), or

2. Configure passwordless sudo for the `akushnir` account on `192.168.168.42` for the following commands: `systemctl`, `journalctl`, `mv`/`cp` into `/etc` (NOPASSWD for those commands). This permits verifier to run non-interactively.

Recommended next steps (automated once resolved)
-----------------------------------------------

- Fetch secret `onprem_ssh_key` from GSM and place with strict permissions on the runner
- SCP the canonical env to `/etc/canonical_secrets.env` and set mode `640`
- `sudo systemctl enable --now canonical-secrets-api.service`
- Re-run `scripts/test/post_deploy_validation.sh` to verify all checks
- Post verification evidence to issue #2594 and close the sign-off loop

If you prefer the automation to perform these steps now, store the SSH key as `onprem_ssh_key` in GSM and reply here; I'll fetch it and complete the run.
