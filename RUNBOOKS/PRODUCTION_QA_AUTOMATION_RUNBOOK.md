# Production QA Automation Runbook

## Purpose

This runbook defines the automated flow to:

1. Shut down on-prem, GCP, AWS, and Azure workloads
2. Validate cleanup and hibernation
3. Execute consolidated QA checks
4. Validate secrets sync and portal/backend health
5. Produce immutable audit artifacts for release review

## Entry Points

- `bash scripts/cloud/cleanup-all-clouds.sh`
- `bash scripts/qa/production-readiness-gate.sh`
- `bash scripts/qa/review-overlap.sh`
- `bash scripts/github/track-production-hardening.sh --repo <owner/repo>`

## Safety Defaults

- Cleanup defaults to dry-run.
- Shutdown execution requires explicit `--execute`.
- Production gate defaults to non-destructive shutdown validation.

## Typical Execution

1. Overlap/code-review pass

```bash
bash scripts/qa/review-overlap.sh
```

2. Full production QA gate (non-destructive)

```bash
bash scripts/qa/production-readiness-gate.sh
```

3. Execute real shutdown/cleanup + strict gating

```bash
bash scripts/qa/production-readiness-gate.sh --execute-shutdown --strict
```

4. Track complete work in GitHub milestone/issues

```bash
bash scripts/github/track-production-hardening.sh --repo <owner/repo> --apply
```

## Artifacts

- QA reports: `reports/qa/`
- Cleanup audit logs: `logs/cleanup/`
- QA logs and errors: `logs/qa/`

## Requirement Mapping

1. On-prem shutdown: `scripts/cloud/onprem-cleanup-complete.sh`
2. Cloud shutdown: `scripts/cloud/gcp-cleanup-complete.sh`, `scripts/cloud/aws-cleanup-complete.sh`, `scripts/cloud/azure-cleanup-complete.sh`
3. Full cleanup orchestration: `scripts/cloud/cleanup-all-clouds.sh`
4. Immutable/ephemeral/idempotent/no-ops: dry-run defaults + JSONL logs + repeat-safe operations
5. Overlap code review: `scripts/qa/review-overlap.sh`
6. Consolidated tests: `scripts/qa/production-readiness-gate.sh`
7. Secrets sync validation: mirror + health checks via production gate
8. Production readiness: gate report output in `reports/qa/`
9. Shutdown/reboot log checks: `--reboot-check` path in cleanup orchestrator
10. Error tracking: `logs/cleanup/*errors*.jsonl` and `logs/qa/*errors*.jsonl`
11. 10x enhancement tracking: generated issues by tracker script
12. Portal/backend sync checks: health URL checks in production gate
13. Commit/push/merge readiness guard: git-state check in production gate
14. GitHub issue/milestone tracking: tracker script
