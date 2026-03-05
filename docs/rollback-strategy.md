Production Rollback Strategy

Principles

- Fast, automated, and safe: detect regressions early and reverse traffic via rollout controller.
- Minimum blast radius: rollback only affected services or segments.
- Forensic-ready: record state, artifacts, and traces at rollback time.

Automatic Rollback Triggers

- Error rate exceeds configured SLO (example: >1% errors for 3 consecutive windows)
- Latency degradation beyond SLO (p95 worsened > 2x baseline)
- Security detection: runtime attack or vulnerable artifact flagged
- Infrastructure failures: node/region degradation

Rollback Mechanisms

- Canary rollback: scale down new replica sets and restore traffic to stable replica set using service mesh / ingress controls.
- Blue/Green rollback: re-route traffic to blue environment and decommission green.
- Partial rollback: rollback only specific clusters or regions if issue is localized.

State & Forensics

- On rollback, capture export of Prometheus window, recent traces for affected requests, pod logs, and system events; attach to the promotion ticket.
- Make artifact/digest and SBOM available for post-mortem.

Human-in-the-loop

- For high-risk rollbacks (PCI, PII), alert runbook owners and require a single-actor approval before rollback.

Post-Rollback

- Create an incident record, optionally an automated postmortem with associated evidence, and mark the build/artifact as blocked for re-promotion until remediation.

Testing Rollback

- Regularly test rollback paths via chaos engineering and platform exercises.