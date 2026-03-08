import re
import time
from typing import Callable, Dict, List, Pattern, Any, Optional


class RemediationAction:
    def __init__(self, name: str, func: Callable[[Dict], Any]):
        self.name = name
        self.func = func


class PredictiveHealer:
    """Pattern-based predictive healer.

    - Register patterns (regex) mapped to remediation actions.
    - Apply remediation when pattern matches and cooldown allows.
    - Cooldown prevents heal-spam.
    """

    def __init__(self, cooldown_seconds: float = 300.0):
        self._rules: List[Dict] = []
        self._cooldown = cooldown_seconds
        self._last_heal: Dict[str, float] = {}

    def register_rule(self, pattern: str, action: RemediationAction):
        compiled: Pattern = re.compile(pattern)
        self._rules.append({"pattern": compiled, "action": action})

    def _is_cooled_down(self, name: str) -> bool:
        last = self._last_heal.get(name)
        if not last:
            return True
        return (time.time() - last) >= self._cooldown

    def evaluate(self, context: Dict) -> List[str]:
        """Evaluate rules against `context` and run remediation actions when
        patterns match and cooldown allows. Returns list of executed action names.
        """
        executed = []
        text = context.get("message", "")
        for rule in self._rules:
            if rule["pattern"].search(text):
                name = rule["action"].name
                if not self._is_cooled_down(name):
                    continue
                # Execute remediation
                try:
                    rule["action"].func(context)
                    executed.append(name)
                    self._last_heal[name] = time.time()
                except Exception:
                    # In production, log and escalate; keep simple here
                    pass
        return executed


__all__ = ["PredictiveHealer", "RemediationAction"]
