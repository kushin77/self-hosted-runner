import time
from typing import Callable, Dict, Any, List


class EscalationManager:
    """Multi-layer escalation manager with simple de-duplication and
    acknowledgment tracking. Real integrations (Slack/PagerDuty/GitHub) are
    provided via callables passed into `notify_*` methods.
    """

    def __init__(self):
        # map key -> last_ts
        self._last_notified: Dict[str, float] = {}
        self._acknowledged: Dict[str, bool] = {}

    def _should_notify(self, key: str, cooldown: float) -> bool:
        last = self._last_notified.get(key)
        if last is None:
            return True
        return (time.time() - last) >= cooldown

    def notify(self, key: str, message: str, level: int = 1,
               slack_fn: Callable[[str], Any] = None,
               github_fn: Callable[[str], Any] = None,
               pagerduty_fn: Callable[[str], Any] = None,
               cooldown: float = 60.0) -> List[str]:
        """Notify through appropriate channels for the given level.

        level mapping (example): 1=Slack, 2=GitHub issue, 3=PagerDuty
        """
        sent = []
        if not self._should_notify(key, cooldown):
            return sent

        if level >= 1 and slack_fn:
            slack_fn(message)
            sent.append("slack")
        if level >= 2 and github_fn:
            github_fn(message)
            sent.append("github")
        if level >= 3 and pagerduty_fn:
            pagerduty_fn(message)
            sent.append("pagerduty")

        self._last_notified[key] = time.time()
        return sent

    def acknowledge(self, key: str):
        self._acknowledged[key] = True

    def is_acknowledged(self, key: str) -> bool:
        return self._acknowledged.get(key, False)


__all__ = ["EscalationManager"]
