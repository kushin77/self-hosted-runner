Rollback playbook for Secrets Orchestrator
========================================

This folder contains an idempotent, dry-run-first rollback script for the
secrets orchestration operator. The intent is to provide a safe playbook that
operators can run to undo automation changes if needed.

Files
- `rollback_secrets_orchestrator.sh` — Main rollback script. Dry-run by
  default; pass `--confirm` to execute destructive steps. Pass `--delete-sa`
  together with `--confirm` to remove the service account.

Usage

1. Dry-run (safe):

```bash
scripts/rollback/rollback_secrets_orchestrator.sh
```

2. Execute rollback (remove SA keys, revoke IAM bindings):

```bash
scripts/rollback/rollback_secrets_orchestrator.sh --confirm
```

3. Execute and delete SA entirely:

```bash
scripts/rollback/rollback_secrets_orchestrator.sh --confirm --delete-sa
```

Notes
- The script writes execution logs to `artifacts/rollback/rollback.log` when
  run with `--confirm`.
- `terraform destroy` is optional and only runs with `--confirm` (and will
  attempt to destroy resources in `infra/secrets-orchestrator`).
- This playbook is intentionally conservative; review before running in
  production.
