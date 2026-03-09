import logging
import hashlib
import json
from typing import Optional, Dict, List, Any
from datetime import datetime, timedelta
from enum import Enum

logger = logging.getLogger(__name__)

class EscalationLevel(Enum):
    SLACK = 1
    GITHUB_ISSUE = 5
    PAGERDUTY = 10
    EXECUTIVE = 20

class Notification:
    def __init__(self, title: str, description: str, error_id: str, context: Optional[Dict[str, Any]] = None):
        self.title = title
        self.description = description
        self.error_id = error_id
        self.context = context or {}
        self.timestamp = datetime.utcnow()
    def to_dict(self) -> Dict[str, Any]:
        return {"title": self.title, "description": self.description, "error_id": self.error_id, "context": self.context, "timestamp": self.timestamp.isoformat()}

class NotificationDeduplicator:
    def __init__(self, dedup_window_seconds: int = 300):
        self.dedup_window = timedelta(seconds=dedup_window_seconds)
        self.seen = {}
    def should_notify(self, notification: Notification) -> bool:
        dedup_key = hashlib.sha256(f"{notification.title}:{notification.error_id}".encode()).hexdigest()
        now = datetime.utcnow()
        if dedup_key in self.seen:
            last_sent = self.seen[dedup_key]
            if now - last_sent < self.dedup_window:
                logger.debug(f"Notification deduplicated")
                return False
        self.seen[dedup_key] = now
        return True

class SlackNotifier:
    def __init__(self, webhook_url: Optional[str] = None):
        import os
        self.webhook_url = webhook_url or os.getenv("SLACK_WEBHOOK_URL")
        self.available = self.webhook_url is not None
    def send(self, notification: Notification) -> bool:
        if not self.available:
            return False
        try:
            import requests
            payload = {"text": notification.title, "blocks": [{"type": "section", "text": {"type": "mrkdwn", "text": f"*{notification.title}*\n{notification.description}"}}]}
            response = requests.post(self.webhook_url, json=payload, timeout=10)
            logger.info(f"Slack notification sent")
            return True
        except Exception as e:
            logger.error(f"Slack notification failed: {e}")
            return False

class GitHubIssueCreator:
    def __init__(self, token: Optional[str] = None, repo: Optional[str] = None):
        import os
        self.token = token or os.getenv("GITHUB_TOKEN")
        self.repo = repo or os.getenv("GITHUB_REPO")
        self.available = self.token is not None and self.repo is not None
        self.created_issues = {}
    def create_or_update_issue(self, notification: Notification) -> Optional[int]:
        if not self.available:
            return None
        try:
            import requests
            existing_issue = self.created_issues.get(notification.error_id)
            if existing_issue:
                return existing_issue
            payload = {"title": notification.title, "body": f"{notification.description}\n\n**Error ID:** {notification.error_id}", "labels": ["self-healing"]}
            url = f"https://api.github.com/repos/{self.repo}/issues"
            headers = {"Authorization": f"token {self.token}"}
            response = requests.post(url, json=payload, headers=headers, timeout=10)
            issue_number = response.json().get("number")
            self.created_issues[notification.error_id] = issue_number
            logger.info(f"GitHub issue created: #{issue_number}")
            return issue_number
        except Exception as e:
            logger.error(f"GitHub issue creation failed: {e}")
            return None

class PagerDutyIncidentCreator:
    def __init__(self, integration_key: Optional[str] = None):
        import os
        self.integration_key = integration_key or os.getenv("PAGERDUTY_INTEGRATION_KEY")
        self.available = self.integration_key is not None
    def create_incident(self, notification: Notification) -> Optional[str]:
        if not self.available:
            return None
        logger.info(f"PagerDuty incident: {notification.title}")
        return notification.error_id

class EscalationOrchestrator:
    def __init__(self):
        self.deduplicator = NotificationDeduplicator()
        self.slack = SlackNotifier()
        self.github = GitHubIssueCreator()
        self.pagerduty = PagerDutyIncidentCreator()
        self.error_counts = {}
    def handle_error(self, title: str, description: str, error_id: str, context: Optional[Dict[str, Any]] = None, environment: str = "production") -> bool:
        notification = Notification(title, description, error_id, context)
        if not self.deduplicator.should_notify(notification):
            return False
        self.error_counts[error_id] = self.error_counts.get(error_id, 0) + 1
        count = self.error_counts[error_id]
        logger.info(f"Escalating error {error_id} (count: {count})")
        if count >= EscalationLevel.SLACK.value:
            self.slack.send(notification)
        if count >= EscalationLevel.GITHUB_ISSUE.value:
            self.github.create_or_update_issue(notification)
        if count >= EscalationLevel.PAGERDUTY.value and environment == "production":
            self.pagerduty.create_incident(notification)
        return True
    def get_escalation_status(self) -> Dict[str, int]:
        return self.error_counts.copy()

_orchestrator = None

def get_escalation_orchestrator() -> EscalationOrchestrator:
    global _orchestrator
    if _orchestrator is None:
        _orchestrator = EscalationOrchestrator()
    return _orchestrator
