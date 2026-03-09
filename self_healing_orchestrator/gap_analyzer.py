import json
from typing import Dict, List, Any, Callable, Optional


class GapReport:
    """Gap analysis report with issues and proposed solutions."""

    def __init__(self):
        self.issues: List[Dict[str, Any]] = []
        self.solutions: List[Dict[str, Any]] = []
        self.severity_summary = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0}

    def add_issue(self, title: str, description: str, severity: str = "MEDIUM",
                  category: str = "unknown"):
        issue = {
            "title": title,
            "description": description,
            "severity": severity,
            "category": category,
        }
        self.issues.append(issue)
        self.severity_summary[severity] = self.severity_summary.get(severity, 0) + 1

    def add_solution(self, issue_title: str, solution: str, priority: int = 0,
                     remediation_fn: Optional[Callable[[], bool]] = None):
        sol = {
            "for_issue": issue_title,
            "solution": solution,
            "priority": priority,
            "remediation_fn": remediation_fn,
        }
        self.solutions.append(sol)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "issues": self.issues,
            "solutions": [
                {k: v for k, v in s.items() if k != "remediation_fn"}
                for s in self.solutions
            ],
            "severity_summary": self.severity_summary,
        }


class GapAnalyzer:
    """Analyzes current state and generates gap analysis with solutions."""

    def __init__(self, validators: Dict[str, Callable[[], bool]]):
        # validators: name -> function returning True if OK, False if gap exists
        self.validators = validators

    def analyze(self) -> GapReport:
        """Run all validators and generate gap report."""
        report = GapReport()
        for validator_name, validator_fn in self.validators.items():
            try:
                result = validator_fn()
                if not result:
                    # Gap detected
                    report.add_issue(
                        title=f"Validator Failed: {validator_name}",
                        description=f"Health check '{validator_name}' failed.",
                        severity="HIGH",
                        category="health-check",
                    )
            except Exception as e:
                report.add_issue(
                    title=f"Validator Exception: {validator_name}",
                    description=f"Validator '{validator_name}' raised: {str(e)}",
                    severity="CRITICAL",
                    category="exception",
                )
        return report


__all__ = ["GapAnalyzer", "GapReport"]
