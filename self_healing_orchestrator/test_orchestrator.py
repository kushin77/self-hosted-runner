import time
import pytest

from self_healing_orchestrator.orchestrator import (
    WorkflowOrchestrator,
    RemediationStep,
    WorkflowSequence,
    StepStatus,
)
from self_healing_orchestrator.gap_analyzer import GapAnalyzer, GapReport
from self_healing_orchestrator.health_validator import HealthValidator
from self_healing_orchestrator.integration import SelfHealingOrchestrationIntegration


def test_remediation_step_success():
    """Test a successful remediation step."""
    called = {"n": 0}

    def action():
        called["n"] += 1
        return True

    step = RemediationStep("test_step", action, max_retries=3)
    result = step.execute()
    assert result is True
    assert step.status == StepStatus.SUCCESS
    assert called["n"] == 1


def test_remediation_step_retry_success():
    """Test remediation step that fails then succeeds."""
    called = {"n": 0}

    def action():
        called["n"] += 1
        return called["n"] >= 2  # Fail first time, succeed second

    step = RemediationStep("retry_step", action, max_retries=3, retry_delay=0.01)
    result = step.execute()
    assert result is True
    assert called["n"] == 2


def test_remediation_step_exhausted_retries():
    """Test remediation step that exhausts retries."""
    def action():
        return False

    step = RemediationStep("fail_step", action, max_retries=2, retry_delay=0.01)
    result = step.execute()
    assert result is False
    assert step.status == StepStatus.FAILED
    assert step.attempts == 2


def test_workflow_sequence_success():
    """Test a sequence of steps that all succeed."""
    seq = WorkflowSequence(
        "seq1",
        [
            RemediationStep("s1", lambda: True),
            RemediationStep("s2", lambda: True),
            RemediationStep("s3", lambda: True),
        ],
    )
    result = seq.execute()
    assert result is True
    assert seq.executed_steps == ["s1", "s2", "s3"]
    assert seq.failed_step is None


def test_workflow_sequence_stop_at_failure():
    """Test that sequence stops at first failure."""
    seq = WorkflowSequence(
        "seq2",
        [
            RemediationStep("s1", lambda: True),
            RemediationStep("s2", lambda: False),
            RemediationStep("s3", lambda: True),
        ],
    )
    result = seq.execute()
    assert result is False
    assert seq.executed_steps == ["s1"]
    assert seq.failed_step == "s2"


def test_orchestrator_success():
    """Test orchestrator with all sequences succeeding."""
    orch = WorkflowOrchestrator()
    seq1 = WorkflowSequence("seq1", [RemediationStep("s1", lambda: True)])
    seq2 = WorkflowSequence("seq2", [RemediationStep("s2", lambda: True)])
    orch.add_sequence(seq1)
    orch.add_sequence(seq2)
    result = orch.execute_all()
    assert result["all_success"] is True
    assert result["completed_sequences"] == ["seq1", "seq2"]
    assert result["failed_sequence"] is None


def test_orchestrator_stops_at_failure():
    """Test orchestrator stops at first failed sequence."""
    orch = WorkflowOrchestrator()
    seq1 = WorkflowSequence("seq1", [RemediationStep("s1", lambda: True)])
    seq2 = WorkflowSequence("seq2", [RemediationStep("s2", lambda: False)])
    seq3 = WorkflowSequence("seq3", [RemediationStep("s3", lambda: True)])
    orch.add_sequence(seq1)
    orch.add_sequence(seq2)
    orch.add_sequence(seq3)
    result = orch.execute_all()
    assert result["all_success"] is False
    assert result["completed_sequences"] == ["seq1"]
    assert result["failed_sequence"] == "seq2"


def test_gap_analyzer():
    """Test gap analyzer."""
    validators = {
        "check1": lambda: True,
        "check2": lambda: False,
    }
    analyzer = GapAnalyzer(validators)
    report = analyzer.analyze()
    assert len(report.issues) == 1
    assert report.severity_summary["HIGH"] == 1


def test_health_validator_all_pass():
    """Test health validator when all critical checks pass."""
    validator = HealthValidator(
        {
            "check1": lambda: True,
            "check2": lambda: True,
        }
    )
    result = validator.validate(max_attempts=1)
    assert result is True


def test_health_validator_retries():
    """Test health validator retries on failure."""
    call_count = {"n": 0}

    def check():
        call_count["n"] += 1
        return call_count["n"] >= 2

    validator = HealthValidator({"retryable": check})
    result = validator.validate(max_attempts=3, delay_between_attempts=0.01)
    assert result is True
    assert call_count["n"] == 2


def test_integration_full_success():
    """Test full integration success."""
    integration = SelfHealingOrchestrationIntegration("dep-123")

    # Add validators
    integration.add_validation_check("health", lambda: True, is_critical=True)

    # Add remediation sequence
    integration.add_remediation_sequence(
        "fix_seq",
        [
            RemediationStep("fix1", lambda: True),
            RemediationStep("fix2", lambda: True),
        ],
    )

    # Execute
    result = integration.execute_full_orchestration()
    assert result["status"] == "success"
    assert result["report"]["status"] == "success"


def test_integration_failed_validation():
    """Test integration failure due to failed validation."""
    integration = SelfHealingOrchestrationIntegration("dep-456")

    # Add a failing validator
    integration.add_validation_check("critical_check", lambda: False, is_critical=True)

    # Add remediation (succeeds, but validation fails)
    integration.add_remediation_sequence(
        "fix_seq", [RemediationStep("fix1", lambda: True)]
    )

    # Execute
    result = integration.execute_full_orchestration()
    assert result["status"] == "failed"
    assert result["reason"] == "health_validation_failed"
