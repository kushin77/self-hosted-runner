import time
import json
import threading
from typing import Callable, Dict, List, Any, Optional
from enum import Enum


class StepStatus(Enum):
    PENDING = "pending"
    IN_PROGRESS = "in-progress"
    SUCCESS = "success"
    FAILED = "failed"
    RETRYING = "retrying"


class RemediationStep:
    """A single remediation step with immediate retry logic."""

    def __init__(self, name: str, action: Callable[[], bool], max_retries: int = 3,
                 retry_delay: float = 1.0):
        self.name = name
        self.action = action
        self.max_retries = max_retries
        self.retry_delay = retry_delay
        self.status = StepStatus.PENDING
        self.attempts = 0
        self.last_error = None

    def execute(self) -> bool:
        """Execute step with immediate retry-on-failure up to max_retries."""
        self.attempts = 0
        while self.attempts < self.max_retries:
            try:
                self.status = StepStatus.IN_PROGRESS
                self.attempts += 1
                result = self.action()
                if result:
                    self.status = StepStatus.SUCCESS
                    return True
                else:
                    self.status = StepStatus.RETRYING
                    if self.attempts < self.max_retries:
                        time.sleep(self.retry_delay)
            except Exception as e:
                self.last_error = str(e)
                self.status = StepStatus.RETRYING
                if self.attempts < self.max_retries:
                    time.sleep(self.retry_delay)
        self.status = StepStatus.FAILED
        return False


class WorkflowSequence:
    """Defines a sequence of remediation steps with dependency tracking."""

    def __init__(self, name: str, steps: List[RemediationStep]):
        self.name = name
        self.steps = steps
        self.executed_steps: List[str] = []
        self.failed_step: Optional[str] = None

    def execute(self) -> bool:
        """Execute all steps in order. Stop at first failure. Return True iff all succeed."""
        for step in self.steps:
            if not step.execute():
                self.failed_step = step.name
                return False
            self.executed_steps.append(step.name)
        return True


class WorkflowOrchestrator:
    """Orchestrates multiple workflow sequences with proper gating and validation."""

    def __init__(self):
        self.sequences: List[WorkflowSequence] = []
        self.audit_trail: List[Dict[str, Any]] = []
        self._lock = threading.Lock()

    def add_sequence(self, seq: WorkflowSequence):
        with self._lock:
            self.sequences.append(seq)

    def execute_all(self) -> Dict[str, Any]:
        """Execute all sequences in order. Do NOT progress until 100% success."""
        result = {
            "completed_sequences": [],
            "failed_sequence": None,
            "all_success": False,
        }
        for seq in self.sequences:
            ts = time.time()
            success = seq.execute()
            audit_entry = {
                "timestamp": ts,
                "sequence": seq.name,
                "success": success,
                "executed_steps": seq.executed_steps,
                "failed_step": seq.failed_step,
            }
            with self._lock:
                self.audit_trail.append(audit_entry)
            if not success:
                result["failed_sequence"] = seq.name
                result["failed_step"] = seq.failed_step
                return result
            result["completed_sequences"].append(seq.name)
        result["all_success"] = True
        return result

    def get_audit_trail(self) -> List[Dict[str, Any]]:
        with self._lock:
            return list(self.audit_trail)


__all__ = ["WorkflowOrchestrator", "RemediationStep", "WorkflowSequence", "StepStatus"]
