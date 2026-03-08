import logging
from typing import Optional, Dict, List, Any
from enum import Enum
from datetime import datetime

logger = logging.getLogger(__name__)

class PRPriority(Enum):
    CRITICAL = "critical"
    HIGH = "high"
    NORMAL = "normal"
    LOW = "low"

class PRClassifier:
    def __init__(self):
        pass
    def classify(self, pr_data: Dict[str, Any]) -> PRPriority:
        risk_score = self._compute_risk_score(pr_data)
        if risk_score < 10:
            return PRPriority.CRITICAL
        elif risk_score < 30:
            return PRPriority.HIGH
        elif risk_score < 60:
            return PRPriority.NORMAL
        else:
            return PRPriority.LOW
    def _compute_risk_score(self, pr_data: Dict[str, Any]) -> float:
        score = 50.0
        changes = pr_data.get("changes", 0)
        if changes < 50:
            score -= 20
        elif changes < 200:
            score -= 10
        elif changes > 1000:
            score += 15
        reviews = pr_data.get("approved_reviews", 0)
        if reviews >= 2:
            score -= 15
        elif reviews == 1:
            score -= 7
        else:
            score += 10
        if pr_data.get("author_is_maintainer", False):
            score -= 10
        coverage = pr_data.get("test_coverage_percent", 50)
        if coverage > 80:
            score -= 10
        elif coverage < 50:
            score += 15
        if pr_data.get("slsa_verified", False):
            score -= 5
        if pr_data.get("target_branch") == "main":
            score += 10
        return max(0, min(100, score))

class MergeScheduler:
    def __init__(self):
        self.pending_merges = {"critical": [], "high": [], "normal": [], "low": []}
    def schedule_merge(self, pr_number: str, priority: PRPriority):
        self.pending_merges[priority.value].append(pr_number)
    def should_merge_now(self, priority: PRPriority) -> bool:
        now = datetime.utcnow()
        if priority == PRPriority.CRITICAL:
            return True
        elif priority == PRPriority.HIGH:
            return now.minute % 15 == 0
        elif priority == PRPriority.NORMAL:
            return now.hour % 4 == 0
        elif priority == PRPriority.LOW:
            return now.hour == 2
        return False

class MergeExecutor:
    def __init__(self):
        pass
    def execute_merge(self, pr_number: str, priority: PRPriority, merge_method: str = "squash") -> bool:
        logger.info(f"Merging PR {pr_number} via {merge_method}")
        return True

_classifier = None
_scheduler = None
_executor = None

def get_pr_classifier() -> PRClassifier:
    global _classifier
    if _classifier is None:
        _classifier = PRClassifier()
    return _classifier

def get_merge_scheduler() -> MergeScheduler:
    global _scheduler
    if _scheduler is None:
        _scheduler = MergeScheduler()
    return _scheduler

def get_merge_executor() -> MergeExecutor:
    global _executor
    if _executor is None:
        _executor = MergeExecutor()
    return _executor
