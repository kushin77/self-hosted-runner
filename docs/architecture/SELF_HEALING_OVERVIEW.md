Self-Healing Framework Overview
==============================

This repository now contains a set of safe, testable building blocks for
implementing a self-healing CI/CD automation platform. Design goals:

- Immutable: audit logs and checkpoints are append-only where possible.
- Ephemeral: temporary artifacts written under `.checkpoints` or ephemeral
  directories and cleaned up by TTL policies.
- Idempotent: remediation actions and rollback must be idempotent.
- No-Ops: components are designed to be automatable and run without manual
  steps once integrated.
- Secrets: authentication and credentials MUST be provided by external
  secret stores (GSM/VAULT/KMS). No secrets are stored in code.

Modules added (scaffolds + tests):

- `self_healing_retry_engine` — `RetryEngine` with exponential backoff,
  jitter and a circuit breaker.
- `self_healing_auto_merge` — `AutoMergeManager` risk-based auto-merge
  scheduling and rollback hooks.
- `self_healing_predictive` — `PredictiveHealer` pattern matcher + remediation
  cooldown.
- `self_healing_state` — `CheckpointStore` for idempotent workflow resumption.
- `self_healing_escalation` — `EscalationManager` for Slack/GitHub/PagerDuty
  integrations with dedup and ack tracking.
- `self_healing_rollback` — `HealthCheckOrchestrator` + `RollbackExecutor`.
- `self_healing_pr_prioritization` — `PRPrioritizer` scheduler + classifier.

Next steps / Integrations:

1. Implement integration adapters for GitHub (merge/PR APIs), Slack
   notifications, PagerDuty, and secret stores (GSM/VAULT/KMS).
2. Add CI pipeline jobs to run unit tests and security scans on Draft issues.
3. Add observability: metrics and tracing for all components.
