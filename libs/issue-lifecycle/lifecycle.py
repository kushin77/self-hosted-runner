#!/usr/bin/env python3
"""
Issue Lifecycle State Machine
Manages issue states: Backlog → In Progress → Review → Done
Based on labels, milestones, and PR associations
"""

import json
import sys
from enum import Enum
from typing import Dict, List, Optional, Set
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta


class IssueState(Enum):
    """Valid issue states"""
    BACKLOG = "backlog"
    IN_PROGRESS = "in-progress"
    REVIEW = "review"
    BLOCKED = "blocked"
    DONE = "done"


class IssueSeverity(Enum):
    """Issue severity levels"""
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class Priority(Enum):
    """MoSCoW priority"""
    P0 = "p0"
    P1 = "p1"
    P2 = "p2"
    P3 = "p3"
    P4 = "p4"


@dataclass
class Issue:
    """Represents a GitHub issue with metadata"""
    number: int
    title: str
    state: IssueState
    labels: Set[str]
    milestone: Optional[str]
    assignee: Optional[str]
    created_at: str
    updated_at: str
    dependencies: List[int]  # Issue numbers this depends on
    blocking: List[int]  # Issue numbers this blocks
    pr_linked: Optional[int] = None
    severity: Optional[IssueSeverity] = None
    priority: Optional[Priority] = None

    def to_dict(self):
        d = asdict(self)
        d['state'] = self.state.value
        d['labels'] = list(d['labels'])
        d['dependencies'] = list(d['dependencies'])
        d['blocking'] = list(d['blocking'])
        if self.severity:
            d['severity'] = self.severity.value
        if self.priority:
            d['priority'] = self.priority.value
        return d


class IssueLifecycle:
    """Manages issue state transitions and automation"""

    def __init__(self):
        self.state_transitions = {
            IssueState.BACKLOG: {IssueState.IN_PROGRESS},
            IssueState.IN_PROGRESS: {IssueState.REVIEW, IssueState.BLOCKED},
            IssueState.REVIEW: {IssueState.DONE, IssueState.IN_PROGRESS, IssueState.BLOCKED},
            IssueState.BLOCKED: {IssueState.IN_PROGRESS, IssueState.REVIEW},
            IssueState.DONE: set(),
        }

    def can_transition(self, current: IssueState, target: IssueState) -> bool:
        """Check if transition is valid"""
        return target in self.state_transitions.get(current, set())

    def get_next_state(self, issue: Issue) -> Optional[IssueState]:
        """Determine next state based on issue metadata"""
        current = issue.state

        # If comment indicates done, transition to DONE
        if current == IssueState.REVIEW and issue.pr_linked:
            return IssueState.DONE if "merged" in issue.labels else None

        # If has blocking dependencies, transition to BLOCKED
        if issue.dependencies and current in {IssueState.BACKLOG, IssueState.IN_PROGRESS}:
            return IssueState.BLOCKED

        # If unblocked from BLOCKED, return to previous state
        if current == IssueState.BLOCKED and not issue.dependencies:
            return IssueState.IN_PROGRESS

        # If assigned and no PR, move to IN_PROGRESS
        if current == IssueState.BACKLOG and issue.assignee:
            return IssueState.IN_PROGRESS

        # If PR exists, move to REVIEW
        if current == IssueState.IN_PROGRESS and issue.pr_linked:
            return IssueState.REVIEW

        return None

    def auto_transition(self, issue: Issue) -> Optional[IssueState]:
        """Auto-transition issue if eligible"""
        next_state = self.get_next_state(issue)
        if next_state and self.can_transition(issue.state, next_state):
            issue.state = next_state
            return next_state
        return None

    def apply_labels_for_state(self, issue: Issue) -> Set[str]:
        """Generate labels based on issue state and metadata"""
        labels = issue.labels.copy()

        # State label
        labels.add(f"state:{issue.state.value}")

        # SLA labels
        created_dt = datetime.fromisoformat(issue.created_at.replace('Z', '+00:00'))
        days_open = (datetime.now(created_dt.tzinfo) - created_dt).days

        if issue.severity == IssueSeverity.CRITICAL:
            if days_open > 1:
                labels.add("sla:breached")
            labels.add("sla:critical-1d")
        elif issue.severity == IssueSeverity.HIGH:
            if days_open > 3:
                labels.add("sla:breached")
            labels.add("sla:high-3d")
        elif issue.severity == IssueSeverity.MEDIUM:
            if days_open > 7:
                labels.add("sla:breached")
            labels.add("sla:medium-7d")
        elif issue.severity == IssueSeverity.LOW:
            if days_open > 14:
                labels.add("sla:breached")
            labels.add("sla:low-14d")

        # Type inference from keywords
        if any(keyword in issue.title.lower() for keyword in ["bug", "broken", "crash", "error"]):
            labels.add("type:bug")
        elif any(keyword in issue.title.lower() for keyword in ["add", "feat", "implement", "support"]):
            labels.add("type:feature")
        elif any(keyword in issue.title.lower() for keyword in ["update", "upgrade", "dep", "library"]):
            labels.add("type:dependencies")
        elif any(keyword in issue.title.lower() for keyword in ["refactor", "cleanup", "reorg"]):
            labels.add("type:chore")
        elif any(keyword in issue.title.lower() for keyword in ["security", "vuln", "cve"]):
            labels.add("type:security")
            labels.add("priority:p0")  # Force P0 for security
        elif any(keyword in issue.title.lower() for keyword in ["compliance", "audit", "cert"]):
            labels.add("type:compliance")

        # Blocked indicator
        if issue.dependencies:
            labels.add("blocked-by-issues")
        if issue.blocking:
            labels.add("blocks-other-issues")

        # Stale indicator
        if days_open > 30 and issue.state in {IssueState.BACKLOG, IssueState.BLOCKED}:
            labels.add("stale")

        return labels


def main():
    """CLI interface"""
    if len(sys.argv) < 2:
        print("Usage: lifecycle.py <command> [args]")
        print("Commands:")
        print("  process-issue <json>  - Process issue JSON and return updated state")
        print("  transition <current> <target> - Check if transition is valid")
        sys.exit(1)

    command = sys.argv[1]
    lifecycle = IssueLifecycle()

    if command == "process-issue":
        issue_json = json.loads(sys.argv[2])
        # Reconstruct issue
        issue = Issue(
            number=issue_json["number"],
            title=issue_json["title"],
            state=IssueState(issue_json["state"]),
            labels=set(issue_json.get("labels", [])),
            milestone=issue_json.get("milestone"),
            assignee=issue_json.get("assignee"),
            created_at=issue_json["created_at"],
            updated_at=issue_json["updated_at"],
            dependencies=issue_json.get("dependencies", []),
            blocking=issue_json.get("blocking", []),
            pr_linked=issue_json.get("pr_linked"),
        )

        # Auto-transition
        next_state = lifecycle.auto_transition(issue)

        # Apply labels
        labels = lifecycle.apply_labels_for_state(issue)

        output = {
            "number": issue.number,
            "current_state": issue.state.value,
            "next_state": next_state.value if next_state else None,
            "labels_to_add": list(labels - issue.labels),
            "labels_to_remove": list(issue.labels - labels),
            "all_labels": sorted(list(labels)),
        }
        print(json.dumps(output, indent=2))

    elif command == "transition":
        current = IssueState(sys.argv[2])
        target = IssueState(sys.argv[3])
        valid = lifecycle.can_transition(current, target)
        print(json.dumps({"valid": valid, "current": current.value, "target": target.value}))


if __name__ == "__main__":
    main()
