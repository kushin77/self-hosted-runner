Self-Healing Orchestrator
==========================

Complete end-to-end orchestration for self-healing CI/CD workflows.

## Features

- **Sequenced Execution**: Workflows run in defined order with proper dependency tracking
- **Immediate Retry**: Steps retry immediately on failure (up to max_retries) before moving on
- **100% Success Gating**: Does NOT progress to next sequence until current one succeeds
- **Gap Analysis**: Identify issues and generate remediation solutions
- **Health Validation**: Verify 100% of critical health checks pass before finishing
- **Immutable Audit Trail**: Complete tracking of all remediation steps and outcomes
- **Deployment Reporting**: Generate comprehensive post-deployment reports à la carte
- **No-Ops**: Fully automated, hands-off orchestration with credential injection via GSM/VAULT/KMS

## Components

- `orchestrator.py` — RemediationStep, WorkflowSequence, WorkflowOrchestrator
- `gap_analyzer.py` — GapAnalyzer and GapReport for issue identification
- `health_validator.py` — HealthValidator for gating progression on critical checks
- `deployment_reporter.py` — DeploymentReporter for post-deployment reporting
- `integration.py` — SelfHealingOrchestrationIntegration: end-to-end integration

## Usage

```python
from self_healing_orchestrator import SelfHealingOrchestrationIntegration, RemediationStep

# Create integration
integration = SelfHealingOrchestrationIntegration("deployment-123", environment="prod")

# Add health checks (critical = must pass)
integration.add_validation_check("endpoint_health", check_endpoint, is_critical=True)
integration.add_validation_check("db_connectivity", check_db, is_critical=True)

# Add remediation sequences
steps = [
    RemediationStep("fix_cache", fix_cache_fn, max_retries=3),
    RemediationStep("restart_service", restart_service_fn, max_retries=2),
]
integration.add_remediation_sequence("recovery_seq", steps)

# Execute full orchestration
result = integration.execute_full_orchestration()

# Generate report
integration.generate_deployment_report("/path/to/report.json")
```

## Orchestration Flow

1. **Gap Analysis**: Validators run to identify issues
2. **Remediation Sequences**: Each sequence runs in order
   - Steps within sequence execute in order
   - Each step retries immediately on failure
   - Sequence stops if any step fails
   - Does NOT proceed to next sequence until current succeeds
3. **Health Validation**: 100% of critical checks must pass
4. **Reporting**: Full audit trail + deployment metrics

## Design

- **Immutable**: Audit trail is append-only JSON
- **Ephemeral**: Checkpoints auto-cleanup via TTL
- **Idempotent**: All remediation actions must be safe to re-run
- **No-Ops**: Fully automated, no manual intervention
- **Secure**: Credentials provided by GSM/VAULT/KMS integration layer
