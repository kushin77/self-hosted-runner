import json
import threading
import time
from typing import Dict, List, Callable, Any, Optional
from .orchestrator import WorkflowOrchestrator, RemediationStep, WorkflowSequence
from .gap_analyzer import GapAnalyzer, GapReport
from .deployment_reporter import DeploymentReporter
from .health_validator import HealthValidator


class SelfHealingOrchestrationIntegration:
    """Complete self-healing orchestration with gap analysis, validation, and reporting."""

    def __init__(self, deployment_id: str, environment: str = "production"):
        self.deployment_id = deployment_id
        self.environment = environment
        self.orchestrator = WorkflowOrchestrator()
        self.reporter = DeploymentReporter(deployment_id, environment)
        self.health_validator: Optional[HealthValidator] = None
        self.gap_analyzer: Optional[GapAnalyzer] = None
        self._lock = threading.Lock()

    def add_validation_check(self, name: str, check_fn: Callable[[], bool],
                             is_critical: bool = True):
        """Add a health check (critical or warning)."""
        if self.health_validator is None:
            self.health_validator = HealthValidator({}, {})
        if is_critical:
            self.health_validator.critical_checks[name] = check_fn
        else:
            self.health_validator.warning_checks[name] = check_fn

    def add_remediation_sequence(self, seq_name: str, steps: List[RemediationStep]):
        """Add a named remediation sequence."""
        seq = WorkflowSequence(seq_name, steps)
        self.orchestrator.add_sequence(seq)

    def set_gap_analyzer(self, analyzer: GapAnalyzer):
        """Set the gap analyzer for post-orchestra analysis."""
        self.gap_analyzer = analyzer

    def execute_full_orchestration(self) -> Dict[str, Any]:
        """Execute full orchestration: gap analysis → remediation → validation."""
        try:
            # Step 1: Gap analysis
            if self.gap_analyzer:
                gap_report = self.gap_analyzer.analyze()
                self.reporter.set_gap_analysis(gap_report.to_dict())

            # Step 2: Execute remediation sequences
            orch_result = self.orchestrator.execute_all()
            self.reporter.add_audit_entry("orchestration_result", orch_result)

            # Step 3: Health validation (100% must pass)
            if self.health_validator:
                if self.health_validator.validate():
                    self.reporter.add_audit_entry("health_validation", "PASSED")
                    self.reporter.finalize(success=True)
                    return {
                        "status": "success",
                        "report": self.reporter.to_dict(),
                    }
                else:
                    self.reporter.add_audit_entry("health_validation", "FAILED")
                    self.reporter.finalize(success=False)
                    return {
                        "status": "failed",
                        "reason": "health_validation_failed",
                        "report": self.reporter.to_dict(),
                    }
            else:
                # No validator; check orchestration result
                if orch_result.get("all_success"):
                    self.reporter.finalize(success=True)
                    return {
                        "status": "success",
                        "report": self.reporter.to_dict(),
                    }
                else:
                    self.reporter.finalize(success=False)
                    return {
                        "status": "failed",
                        "reason": orch_result.get("failed_sequence"),
                        "report": self.reporter.to_dict(),
                    }
        except Exception as e:
            self.reporter.add_audit_entry("orchestration_exception", str(e))
            self.reporter.finalize(success=False)
            return {
                "status": "failed",
                "reason": "exception",
                "error": str(e),
                "report": self.reporter.to_dict(),
            }

    def generate_deployment_report(self, filepath: str):
        """Save deployment report to file."""
        self.reporter.save_to_file(filepath)


__all__ = ["SelfHealingOrchestrationIntegration"]
