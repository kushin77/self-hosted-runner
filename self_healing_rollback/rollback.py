import time
from typing import Callable, Dict, Any, List


class RollbackExecutor:
    """Executes rollback strategies (blue-green/canary) via provided
    callables. Rollbacks must be idempotent and validate after execution.
    """

    def __init__(self):
        pass

    def execute_rollback(self, deployment_id: str, rollback_fn: Callable[[str], Any]):
        # In production, implement blue-green/canary logic; keep simple here
        return rollback_fn(deployment_id)


class HealthCheckOrchestrator:
    """Runs a set of health checks and triggers rollback when thresholds are
    exceeded.
    """

    def __init__(self, checks: Dict[str, Callable[[], bool]]):
        # checks: name -> callable returning True if healthy
        self.checks = checks

    def run_checks(self) -> Dict[str, bool]:
        results = {}
        for name, fn in self.checks.items():
            try:
                results[name] = bool(fn())
            except Exception:
                results[name] = False
        return results

    def should_rollback(self, results: Dict[str, bool], error_rate_threshold: float = 0.05) -> bool:
        # Simplified: rollback when any essential check fails or when
        # proportion of failing checks exceeds threshold
        total = len(results)
        failed = sum(1 for v in results.values() if not v)
        if failed == 0:
            return False
        if failed / total >= error_rate_threshold:
            return True
        return False


__all__ = ["RollbackExecutor", "HealthCheckOrchestrator"]
