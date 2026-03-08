import time
import threading
from typing import Callable, Any, Dict, Optional


class MergeRejected(Exception):
    pass


class AutoMergeManager:
    """AutoMergeManager performs risk-based decisions. This is a safely
    pluggable manager: actual GitHub/Git operations should be implemented in
    integration adapters that call into this manager.
    """

    def __init__(self, risk_classifier: Optional[Callable[[Dict], str]] = None):
        # risk_classifier receives PR metadata and returns 'CRITICAL'|'MEDIUM'|'LOW'
        self.risk_classifier = risk_classifier or (lambda pr: "NORMAL")
        self._locks = {}

    def assess(self, pr: Dict) -> str:
        return self.risk_classifier(pr)

    def schedule_merge(self, pr: Dict, merge_func: Callable[[Dict], Any], delay_seconds: float = 0):
        tier = self.assess(pr)
        if tier == "CRITICAL":
            raise MergeRejected("CRITICAL PRs require manual review")

        def worker():
            if delay_seconds:
                time.sleep(delay_seconds)
            # Execute merge function provided by integration layer
            return merge_func(pr)

        t = threading.Thread(target=worker, daemon=True)
        t.start()
        return t

    def rollback_hook(self, pr: Dict, rollback_func: Callable[[Dict], Any]):
        # Placeholder: in production, this would ensure idempotent rollback
        return rollback_func(pr)


__all__ = ["AutoMergeManager", "MergeRejected"]
