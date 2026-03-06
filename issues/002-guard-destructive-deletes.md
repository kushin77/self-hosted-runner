Title: Guard destructive deletes with safe_delete wrapper

Description
- Replace direct `rm -rf` calls across scripts with `scripts/safe_delete.sh` wrapper which requires explicit `--confirm` and defaults to `--dry-run`.

Acceptance
- Identify and replace high-risk `rm -rf` occurrences.
- Update CI/CD runbooks to require the wrapper and to document how to perform an approved delete.

Owner: infra-team
Priority: high
