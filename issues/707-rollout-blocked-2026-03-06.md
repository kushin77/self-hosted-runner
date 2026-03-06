# Rollout attempt blocked — 2026-03-06

Summary:
- Attempted full staged rollout (dry-run succeeded) using `./scripts/deploy-rotation-staging.sh` against `ansible/inventory/staging` (localhost).
- Dry-run (`--check`) completed successfully.
- Full apply failed during `Gathering Facts` with error: `sudo: a password is required`.

Command run:
```
./scripts/deploy-rotation-staging.sh --inventory ansible/inventory/staging --check --verbose && \
./scripts/deploy-rotation-staging.sh --inventory ansible/inventory/staging --verbose
```

Key failure excerpt:
```
fatal: [localhost]: FAILED! => {"ansible_facts": {}, "changed": false, "failed_modules": {"ansible.legacy.setup": {"ansible_facts": {"discovered_interpreter_python": "/usr/bin/python3"}, "failed": true, "module_stderr": "sudo: a password is required\n", "module_stdout": "", "msg": "MODULE FAILURE\nSee stdout/stderr for the exact error", "rc": 1}}, "msg": "The following modules failed to execute: ansible.legacy.setup\n"}
```

Recommended next steps (pick one):
- Provide SSH inventory + `ANSIBLE_SSH_KEY` (private key stored in a secret) and ensure the deploy user has `NOPASSWD` sudo for required commands.
- Enable passwordless sudo for the local deploy user for the required operations.
- Dispatch the deploy via GitHub Actions workflow with repository secrets configured (preferred for CI-driven, auditable runs).

Actions taken:
- Updated `scripts/deploy-rotation-staging.sh` to accept `ANSIBLE_SSH_KEY` / `--ssh-key-file` and `ANSIBLE_USER` for non-interactive runs.
- Created this issue note to capture the blocking error and next steps.

Next action (blocked until credentials/sudo provided):
- Re-run the apply step non-interactively and validate metrics (`runner_rotation_failures == 0`, `vault_rotation_success_total` increments).

/cc @ops
