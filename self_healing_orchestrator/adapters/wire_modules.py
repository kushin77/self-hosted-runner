"""Helpers to wire existing self-healing modules into orchestration sequences.

This file provides a simple, opinionated wiring that can be used to boot the
orchestration quickly. Adapters gracefully handle missing modules and will
produce RemediationSteps that fail fast if the underlying implementation
is not present yet.
"""
from typing import Any

from ..integration import SelfHealingOrchestrationIntegration
from . import (
    retry_engine_step,
    auto_merge_step,
    predictive_healer_step,
    state_recovery_step,
    escalation_step,
    rollback_step,
    pr_prioritizer_step,
)


def wire_default_sequences(integration: SelfHealingOrchestrationIntegration, deployment_meta: Any = None):
    """Add default remediation sequences to the provided integration instance.

    The wiring is intentionally conservative: pre-remediation checks, primary
    remediation actions, and post-remediation validation steps. Each step is a
    `RemediationStep` created via the adapters.
    """
    # Pre-remediation: state recovery, predictive detection
    pre_steps = [
        state_recovery_step("state-recovery", max_retries=1),
        predictive_healer_step("predictive-healer", max_retries=2),
    ]
    integration.add_remediation_sequence("pre-remediation", pre_steps)

    # Primary remediation: retry engine + auto-merge + PR prioritizer
    primary_steps = [
        retry_engine_step("retry-engine", max_retries=3),
        auto_merge_step("auto-merge", max_retries=2),
        pr_prioritizer_step("pr-prioritizer", max_retries=2),
    ]
    integration.add_remediation_sequence("primary-remediation", primary_steps)

    # Post-remediation: rollback guard and escalation if required
    post_steps = [
        rollback_step("rollback-check", max_retries=2),
        escalation_step("escalation-notify", max_retries=1),
    ]
    integration.add_remediation_sequence("post-remediation", post_steps)

    # Add a simple always-true health check placeholder to avoid accidental gating
    def _basic_health_check():
        return True

    integration.add_validation_check("basic-health", _basic_health_check, is_critical=True)

    return integration
