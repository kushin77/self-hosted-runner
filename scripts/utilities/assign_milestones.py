#!/usr/bin/env python3
"""
assign_milestones.py - Apply milestone assignments from classification JSON.

Usage:
  assign_milestones.py <classification_json_file> <repo> [--failure-threshold N]

Example:
  assign_milestones.py classification.json kushin77/self-hosted-runner --failure-threshold 10
"""

import json
import subprocess
import sys
import os
from typing import Dict, List

def assign_issues(classification: Dict, repo: str, failure_threshold: int = 10) -> int:
    """
    Apply milestone assignments based on classification.
    
    Returns:
        0 if successful, non-zero if failure threshold exceeded
    """
    assigned = 0
    failed = 0
    failed_issues = []
    
    for milestone, items in classification.items():
        if milestone == 'unassigned':
            # Assign to fallback
            milestone_name = 'Backlog Triage'
            issues = items
        else:
            milestone_name = milestone
            issues = items
        
        for item in issues:
            issue_num = item['number']
            score = item.get('score')
            
            # Attempt assignment
            result = subprocess.run(
                ['gh', 'issue', 'edit', str(issue_num), '--milestone', milestone_name],
                capture_output=True, text=True
            )
            
            if result.returncode == 0:
                assigned += 1
                print(f"✓ #{issue_num} → {milestone_name} (score: {score})")
            else:
                failed += 1
                failed_issues.append(issue_num)
                error_msg = result.stderr[:80].replace('\n', ' ')
                print(f"✗ #{issue_num} → {milestone_name} FAILED: {error_msg}")
            
            if failed >= failure_threshold:
                print(f"⚠ Failure threshold ({failure_threshold}) reached; aborting")
                break
        
        if failed >= failure_threshold:
            break
    
    print(f"\nResult: {assigned} assigned, {failed} failed")
    
    if failed_issues:
        print(f"Failed issues: {failed_issues[:10]}")
    
    return 0 if failed == 0 else 1


def main():
    if len(sys.argv) < 3:
        print("Usage: assign_milestones.py <classification_json_file> <repo> [--failure-threshold N]")
        sys.exit(1)
    
    classification_file = sys.argv[1]
    repo = sys.argv[2]
    failure_threshold = 10
    
    # Parse options
    for arg in sys.argv[3:]:
        if arg.startswith('--failure-threshold='):
            failure_threshold = int(arg.split('=')[1])
    
    # Load classification
    try:
        with open(classification_file, 'r') as f:
            classification = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"ERROR: Failed to load classification file: {e}")
        sys.exit(1)
    
    # Apply assignments
    return assign_issues(classification, repo, failure_threshold)


if __name__ == '__main__':
    sys.exit(main())
