import time
from typing import Dict, Callable, List, Any, Optional


class HealthValidator:
    """Validates that 100% of critical health checks pass before progression."""

    def __init__(self, critical_checks: Dict[str, Callable[[], bool]],
                 warning_checks: Optional[Dict[str, Callable[[], bool]]] = None):
        self.critical_checks = critical_checks
        self.warning_checks = warning_checks or {}
        self.last_results: Dict[str, Any] = {}

    def validate(self, max_attempts: int = 5, delay_between_attempts: float = 2.0) -> bool:
        """Validate that all critical checks pass. Retry up to max_attempts."""
        for attempt in range(max_attempts):
            self.last_results = {"attempt": attempt + 1}
            all_pass = True
            for check_name, check_fn in self.critical_checks.items():
                try:
                    result = bool(check_fn())
                    self.last_results[f"critical_{check_name}"] = result
                    if not result:
                        all_pass = False
                except Exception as e:
                    self.last_results[f"critical_{check_name}_error"] = str(e)
                    all_pass = False

            if all_pass:
                # All critical checks passed
                for check_name, check_fn in self.warning_checks.items():
                    try:
                        result = bool(check_fn())
                        self.last_results[f"warning_{check_name}"] = result
                    except Exception as e:
                        self.last_results[f"warning_{check_name}_error"] = str(e)
                return True

            if attempt < max_attempts - 1:
                time.sleep(delay_between_attempts)

        return False

    def get_results(self) -> Dict[str, Any]:
        return self.last_results


__all__ = ["HealthValidator"]
