#!/usr/bin/env python3
"""Create a GitHub issue alert if the milestone organizer fails.

Usage: python3 milestone_organizer_alert.py --status <EXIT_CODE> --repo <OWNER/REPO>
       python3 milestone_organizer_alert.py --status 2 --repo kushin77/self-hosted-runner

If exit status is non-zero, creates a GitHub issue with failure details.
Requires GH_TOKEN env var or gh auth configured.
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime


def create_failure_issue(repo, status, artifacts_dir):
    """Create a GitHub issue for organizer failure."""
    ts = datetime.utcnow().isoformat() + "Z"
    title = f"⚠️ milestone-organizer failure (exit code {status})"
    
    # Build body with diagnostic info
    body_lines = [
        f"**Status:** exit code {status}",
        f"**Timestamp:** {ts}",
        f"**Host:** {os.getenv('HOSTNAME', 'unknown')}",
        f"**Artifacts:** {artifacts_dir}",
        "",
        "**Diagnostic steps:**",
        "1. Check systemd logs: `sudo journalctl -xeu milestone-organizer.service`",
        "2. Review audit: `tail -f artifacts/milestones-assignments/assignments_*.jsonl`",
        "3. Run manually: `MIN_SCORE=2 REASSIGN=1 bash scripts/automation/run_milestone_organizer.sh`",
        "",
        "**Mitigation:**",
        "- Run rollback: `python3 scripts/utilities/undo_milestone_assignments.py --patch artifacts/milestones-assignments/last_assignment_patch.jsonl --confirm`",
        "- Check credential availability (GSM/Vault/KMS)",
        "- Verify GitHub token and repo access",
    ]
    
    body = "\n".join(body_lines)
    
    # Create issue using gh CLI
    cmd = ["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        print(f"Created issue: {result.stdout.strip()}")
        return 0
    else:
        print(f"Failed to create issue: {result.stderr}")
        return 1


def main():
    parser = argparse.ArgumentParser(description="Create alerts for milestone organizer failures")
    parser.add_argument("--status", type=int, required=True, help="Exit status code")
    parser.add_argument("--repo", default="kushin77/self-hosted-runner", help="GitHub repo (owner/name)")
    parser.add_argument("--artifacts-dir", default="artifacts/milestones-assignments", help="Artifacts directory")
    args = parser.parse_args()
    
    # Only alert on failure
    if args.status == 0:
        print("Exit status 0 (success); no alert needed")
        return 0
    
    # Ensure gh auth works
    auth_check = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True)
    if auth_check.returncode != 0:
        print("gh auth not available; skipping alert")
        return 1
    
    return create_failure_issue(args.repo, args.status, args.artifacts_dir)


if __name__ == "__main__":
    sys.exit(main())
