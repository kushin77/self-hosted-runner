#!/usr/bin/env python3
"""
Issue CLI Tool
Manage GitHub issues with lifecycle automation, labeling, and reporting
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import os


class IssueCLI:
    """CLI interface for issue management"""

    def __init__(self, repo: str = None):
        self.repo = repo or self._get_default_repo()
        self.gh = ["gh", "--repo", self.repo] if repo else ["gh"]

    def _get_default_repo(self) -> str:
        """Get repo from git config or environment"""
        result = subprocess.run(
            ["git", "config", "--get", "remote.origin.url"],
            capture_output=True,
            text=True,
            cwd=os.getcwd()
        )
        if result.returncode == 0:
            url = result.stdout.strip()
            # Extract owner/repo from git URL
            if "github.com" in url:
                parts = url.split(":")[-1].rstrip(".git").split("/")
                return f"{parts[-2]}/{parts[-1]}"
        return os.getenv("GITHUB_REPOSITORY", "")

    def run_gh_api(self, *args) -> Dict:
        """Run gh API command and return JSON"""
        cmd = self.gh + list(args)
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error: {result.stderr}", file=sys.stderr)
            return {}
        return json.loads(result.stdout) if result.stdout else {}

    def list_issues(self, state="open", labels=None, milestone=None, assignee=None, 
                    sort="created", limit=50) -> List[Dict]:
        """List issues with filters"""
        args = ["issue", "list", "--state", state, "--json", 
                "number,title,state,labels,milestone,assignees,createdAt"]
        
        if labels:
            args.extend(["--label", ",".join(labels)])
        if milestone:
            args.extend(["--milestone", milestone])
        if assignee:
            args.extend(["--assignee", assignee])
        
        args.extend(["--limit", str(limit)])
        
        result = subprocess.run(self.gh + args, capture_output=True, text=True)
        return json.loads(result.stdout) if result.returncode == 0 else []

    def get_issue(self, number: int) -> Dict:
        """Get issue details"""
        result = subprocess.run(
            self.gh + ["issue", "view", str(number), "--json", 
                      "number,title,body,state,labels,milestone,assignees,createdAt,updatedAt"],
            capture_output=True, text=True
        )
        return json.loads(result.stdout) if result.returncode == 0 else {}

    def add_label(self, issue: int, labels: List[str]) -> bool:
        """Add labels to issue"""
        result = subprocess.run(
            self.gh + ["issue", "edit", str(issue), "--add-label", ",".join(labels)],
            capture_output=True, text=True
        )
        return result.returncode == 0

    def remove_label(self, issue: int, labels: List[str]) -> bool:
        """Remove labels from issue"""
        result = subprocess.run(
            self.gh + ["issue", "edit", str(issue), "--remove-label", ",".join(labels)],
            capture_output=True, text=True
        )
        return result.returncode == 0

    def assign_issue(self, issue: int, assignees: List[str]) -> bool:
        """Assign issue to users"""
        result = subprocess.run(
            self.gh + ["issue", "edit", str(issue), "--add-assignee", ",".join(assignees)],
            capture_output=True, text=True
        )
        return result.returncode == 0

    def set_milestone(self, issue: int, milestone: str) -> bool:
        """Set milestone"""
        result = subprocess.run(
            self.gh + ["issue", "edit", str(issue), "--milestone", milestone],
            capture_output=True, text=True
        )
        return result.returncode == 0

    def transition_state(self, issue: int, new_state: str) -> bool:
        """Transition issue state"""
        issue_data = self.get_issue(issue)
        current_labels = {l["name"] for l in issue_data.get("labels", [])}
        
        # Remove old state label
        old_state_labels = [l for l in current_labels if l.startswith("state:")]
        if old_state_labels:
            self.remove_label(issue, old_state_labels)
        
        # Add new state label
        return self.add_label(issue, [f"state:{new_state}"])

    def report_velocity(self, days: int = 7, milestone: Optional[str] = None) -> None:
        """Report team velocity"""
        since = (datetime.now() - timedelta(days=days)).isoformat()
        
        # Get closed issues
        closed = self.list_issues(state="closed", limit=200)
        closed_in_period = [
            i for i in closed 
            if datetime.fromisoformat(i["updatedAt"].replace('Z', '+00:00')) > 
               datetime.fromisoformat(since.replace('Z', '+00:00'))
        ]
        
        if milestone:
            closed_in_period = [i for i in closed_in_period 
                              if i.get("milestone", {}).get("title") == milestone]
        
        # Calculate metrics
        total_closed = len(closed_in_period)
        
        bugs = [i for i in closed_in_period 
               if any(l["name"] == "type:bug" for l in i.get("labels", []))]
        features = [i for i in closed_in_period 
                   if any(l["name"] == "type:feature" for l in i.get("labels", []))]
        
        # Calculate avg time to close
        times_to_close = []
        for issue in closed_in_period:
            created = datetime.fromisoformat(issue["createdAt"].replace('Z', '+00:00'))
            updated = datetime.fromisoformat(issue["updatedAt"].replace('Z', '+00:00'))
            ttc = (updated - created).total_seconds() / 86400  # Convert to days
            times_to_close.append(ttc)
        
        avg_ttc = sum(times_to_close) / len(times_to_close) if times_to_close else 0
        
        print(f"\n📊 Velocity Report (Last {days} days)")
        if milestone:
            print(f"   Milestone: {milestone}")
        print(f"   ✅ Total Closed: {total_closed}")
        print(f"   🐛 Bugs: {len(bugs)}")
        print(f"   ✨ Features: {len(features)}")
        print(f"   ⏱️  Avg Time-to-Close: {avg_ttc:.1f} days")
        print()

    def report_sla_violations(self) -> None:
        """Report SLA violations"""
        open_issues = self.list_issues(state="open", limit=200)
        
        violations = []
        for issue in open_issues:
            created = datetime.fromisoformat(issue["createdAt"].replace('Z', '+00:00'))
            age_days = (datetime.now(created.tzinfo) - created).days
            
            labels = {l["name"] for l in issue.get("labels", [])}
            
            # Check SLAs
            if "type:security" in labels and age_days > 1:
                violations.append((issue["number"], "security", age_days))
            elif "type:bug" in labels:
                severity = next((l.split(":")[1] for l in labels if l.startswith("severity:")), "medium")
                limits = {"critical": 1, "high": 3, "medium": 7, "low": 14}
                limit = limits.get(severity, 7)
                if age_days > limit:
                    violations.append((issue["number"], f"bug({severity})", age_days))
        
        if violations:
            print(f"\n🚨 SLA Violations ({len(violations)})")
            for num, vtype, age in sorted(violations, key=lambda x: -x[2])[:20]:
                print(f"   #{num}: {vtype} ({age}d old)")
            print()
        else:
            print("✅ No SLA violations\n")

    def bulk_assign_by_labels(self, label_map: Dict[str, str]) -> None:
        """Bulk assign issues by label pattern"""
        all_issues = self.list_issues(state="open", limit=500)
        
        count = 0
        for issue in all_issues:
            labels = {l["name"] for l in issue.get("labels", [])}
            
            for pattern, assignee in label_map.items():
                if pattern in labels:
                    if self.assign_issue(issue["number"], [assignee]):
                        print(f"✓ Assigned #{issue['number']} to {assignee}")
                        count += 1
                    break
        
        print(f"\nAssigned {count} issues\n")

    def generate_issue_report(self, output_format="markdown") -> None:
        """Generate comprehensive issue report"""
        all_issues = self.list_issues(state="open", limit=500)
        
        # Group by state
        by_state = {}
        for issue in all_issues:
            labels = {l["name"] for l in issue.get("labels", [])}
            state = next((l.split(":")[1] for l in labels if l.startswith("state:")), "backlog")
            if state not in by_state:
                by_state[state] = []
            by_state[state].append(issue)
        
        if output_format == "markdown":
            print("\n# 📊 Open Issues Report\n")
            for state in ["in-progress", "review", "blocked", "backlog"]:
                if state in by_state:
                    issues = by_state[state]
                    print(f"## {state.title()} ({len(issues)})\n")
                    for issue in issues[:10]:  # Top 10
                        labels = [l["name"] for l in issue.get("labels", [])]
                        label_str = " ".join(f"`{l}`" for l in labels[:3])
                        print(f"- #{issue['number']}: {issue['title'][:60]} {label_str}")
                    if len(issues) > 10:
                        print(f"- ... and {len(issues) - 10} more")
                    print()
        elif output_format == "json":
            print(json.dumps({"issues_by_state": by_state}, indent=2))


def main():
    parser = argparse.ArgumentParser(description="GitHub Issue Management CLI")
    parser.add_argument("--repo", help="GitHub repository (owner/repo)")
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    
    # list command
    list_cmd = subparsers.add_parser("list", help="List issues")
    list_cmd.add_argument("--state", default="open", choices=["open", "closed", "all"])
    list_cmd.add_argument("--label", nargs="+", help="Filter by labels")
    list_cmd.add_argument("--milestone", help="Filter by milestone")
    list_cmd.add_argument("--sort", default="created", choices=["created", "updated", "comments"])
    
    # transition command
    transit_cmd = subparsers.add_parser("transition", help="Transition issue state")
    transit_cmd.add_argument("number", type=int)
    transit_cmd.add_argument("state", help="New state")
    
    # assign command
    assign_cmd = subparsers.add_parser("assign", help="Assign issue")
    assign_cmd.add_argument("number", type=int)
    assign_cmd.add_argument("assignees", nargs="+")
    
    # label command
    label_cmd = subparsers.add_parser("label", help="Add/remove labels")
    label_cmd.add_argument("number", type=int)
    label_cmd.add_argument("--add", nargs="+")
    label_cmd.add_argument("--remove", nargs="+")
    
    # velocity command
    velocity_cmd = subparsers.add_parser("velocity", help="Report velocity")
    velocity_cmd.add_argument("--days", type=int, default=7)
    velocity_cmd.add_argument("--milestone", help="Filter by milestone")
    
    # sla command
    subparsers.add_parser("sla", help="Report SLA violations")
    
    # report command
    report_cmd = subparsers.add_parser("report", help="Generate report")
    report_cmd.add_argument("--format", default="markdown", choices=["markdown", "json"])
    
    # bulk-assign command
    bulk_cmd = subparsers.add_parser("bulk-assign", help="Bulk assign by label")
    bulk_cmd.add_argument("--map", required=True, help="JSON map of label->assignee")
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    cli = IssueCLI(repo=args.repo)
    
    if args.command == "list":
        issues = cli.list_issues(
            state=args.state,
            labels=args.label,
            milestone=args.milestone,
            sort=args.sort
        )
        for issue in issues:
            labels = ", ".join(l["name"] for l in issue.get("labels", [])[:3])
            print(f"#{issue['number']:5} [{issue['state']:6}] {issue['title'][:60]:60} {labels}")
    
    elif args.command == "transition":
        if cli.transition_state(args.number, args.state):
            print(f"✓ Transitioned #{args.number} to {args.state}")
        else:
            print(f"✗ Failed to transition #{args.number}")
    
    elif args.command == "assign":
        if cli.assign_issue(args.number, args.assignees):
            print(f"✓ Assigned #{args.number} to {', '.join(args.assignees)}")
    
    elif args.command == "label":
        if args.add:
            cli.add_label(args.number, args.add)
            print(f"✓ Added labels to #{args.number}")
        if args.remove:
            cli.remove_label(args.number, args.remove)
            print(f"✓ Removed labels from #{args.number}")
    
    elif args.command == "velocity":
        cli.report_velocity(days=args.days, milestone=args.milestone)
    
    elif args.command == "sla":
        cli.report_sla_violations()
    
    elif args.command == "report":
        cli.generate_issue_report(output_format=args.format)
    
    elif args.command == "bulk-assign":
        label_map = json.loads(args.map)
        cli.bulk_assign_by_labels(label_map)


if __name__ == "__main__":
    main()
