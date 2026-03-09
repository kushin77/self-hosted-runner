import json
import time
from typing import Dict, Any, List, Optional
from datetime import datetime


class DeploymentReporter:
    """Generates post-deployment reports and remediation ala carte."""

    def __init__(self, deployment_id: str, environment: str = "production"):
        self.deployment_id = deployment_id
        self.environment = environment
        self.start_time = time.time()
        self.report: Dict[str, Any] = {
            "deployment_id": deployment_id,
            "environment": environment,
            "start_time": self.start_time,
            "end_time": None,
            "duration_seconds": None,
            "status": "in-progress",
            "remediation_steps": [],
            "gap_analysis": None,
            "audit_trail": [],
            "metrics": {},
        }

    def add_remediatior_step(self, step_name: str, status: str, duration: float,
                              error: Optional[str] = None):
        """Record a remediation step execution."""
        entry = {
            "step": step_name,
            "status": status,
            "duration_seconds": duration,
            "error": error,
            "timestamp": time.time(),
        }
        self.report["remediation_steps"].append(entry)

    def set_gap_analysis(self, gap_data: Dict[str, Any]):
        """Attach gap analysis to the report."""
        self.report["gap_analysis"] = gap_data

    def add_audit_entry(self, key: str, value: Any):
        """Add a free-form audit entry."""
        self.report["audit_trail"].append({"key": key, "value": value, "ts": time.time()})

    def set_metrics(self, metrics: Dict[str, Any]):
        """Set deployment metrics."""
        self.report["metrics"] = metrics

    def finalize(self, success: bool):
        """Mark deployment as complete."""
        self.report["end_time"] = time.time()
        self.report["duration_seconds"] = self.report["end_time"] - self.start_time
        self.report["status"] = "success" if success else "failed"

    def to_json(self) -> str:
        """Serialize report to JSON."""
        return json.dumps(self.report, default=str, indent=2)

    def to_dict(self) -> Dict[str, Any]:
        """Return as dict."""
        return self.report

    def save_to_file(self, filepath: str):
        """Save report to file."""
        with open(filepath, "w") as f:
            f.write(self.to_json())


__all__ = ["DeploymentReporter"]
