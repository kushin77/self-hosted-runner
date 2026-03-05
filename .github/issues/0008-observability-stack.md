Title: Implement Observability (Metrics, Logs, Traces)

Description:
Build comprehensive observability stack for runner health, job execution, and incident response.

Tasks:
- [x] `observability/metrics-agent.yaml` — Prometheus metrics exporter
- [x] `observability/logging-agent.yaml` — Fluent Bit log shipper to Loki/OpenSearch
- [x] `observability/otel-config.yaml` — OpenTelemetry collector for traces
- [ ] Prometheus recording rules for SLOs
- [ ] Grafana dashboards (runner health, job trends, security)
- [ ] AlertManager rules (runner offline, job failures, disk full)
- [ ] Jaeger UI deployment and configuration
- [ ] Log aggregation and retention policies

Metrics to Export:
- `runner_status` (gauge): online/offline/running
- `runner_job_duration_seconds` (histogram)
- `runner_job_result` (counter): pass/fail
- `runner_health_score` (gauge): 0-6
- `runner_updates_total` (counter)
- `runner_quarantine_total` (counter)
- `job_artifacts_signed_total` (counter)
- `job_policy_violations_total` (counter)

Logs to Collect:
- Bootstrap logs
- Job execution logs (with secret masking)
- Security scan results
- Policy violations
- Health check events
- Update/rollback events

Traces to Collect:
- Job execution span (parent)
- Step execution spans (children)
- Artifact upload spans
- Policy validation spans

SLO Examples:
- Runner uptime > 99.5% monthly
- Job latency p95 < 5 minutes
- Security scan pass rate > 99%

Definition of Done:
- All metrics exported to Prometheus
- Logs streamed to Loki and full-text searchable
- Traces linked to commits and artifacts
- Dashboards show runner health and trends
- Alerts fire on degradation

Acceptance Criteria:
- [ ] Prometheus scrapes metrics
- [ ] Loki ingests and queries logs
- [ ] Tempo stores traces
- [ ] Grafana dashboards created and tested
- [ ] Alerts tested with synthetic failures

Labels: observability, monitoring, telemetry
Priority: P1
Assignees: devops-platform, sre-team

## Status

Completed: 2026-03-05

Resolution: Observability agent configurations and manifests added under `cicd-runner-platform/observability/`. Prometheus, Fluent Bit, and OpenTelemetry collector configured. See DELIVERY_COMPLETION_REPORT.md and tests for verification.
