from typing import Dict, Callable, Any
import threading
import time


class PRPrioritizer:
    """Simple PR prioritizer and scheduler. Classifier is pluggable.

    Scheduler runs merges (via provided merge_fn) according to priorities.
    """

    def __init__(self, classifier: Callable[[Dict], str] = None):
        self.classifier = classifier or (lambda pr: "NORMAL")
        self._locks = {}

    def classify(self, pr: Dict) -> str:
        return self.classifier(pr)

    def schedule(self, pr: Dict, merge_fn: Callable[[Dict], Any], priority_windows: Dict[str, float] = None):
        tier = self.classify(pr)
        # priority_windows example: {"CRITICAL": 0, "HIGH": 900, "NORMAL": 3600}
        delay = 0
        if priority_windows and tier in priority_windows:
            delay = priority_windows[tier]

        def worker():
            if delay:
                time.sleep(delay)
            return merge_fn(pr)

        t = threading.Thread(target=worker, daemon=True)
        t.start()
        return t


__all__ = ["PRPrioritizer"]
