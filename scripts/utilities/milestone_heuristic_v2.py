#!/usr/bin/env python3
"""
Milestone Heuristic Module v2 - Single source of truth for milestone classification.

Features:
- Confidence threshold (min_score configurable)
- Tie-breaking via priority order
- Label-based routing (priority-first)
- Scoring with signal strength
- Reassignment mode for low-confidence issues
"""

import json
import os
import sys
from typing import Optional, Tuple, List, Dict

# === CONFIGURATION ===

MILESTONE_GROUPS = {
    'Observability & Provisioning': [
        'observab', 'provision', 'agent', 'filebeat',
        'node_exporter', 'vault-agent', 'provisioning'
    ],
    'Secrets & Credential Management': [
        'secret', 'secrets', 'aws', 'secretsmanager', 'gsm',
        'vault', 'kms', 'credential', 'gitleaks', 'secrets found', 'rotate'
    ],
    'Deployment Automation & Migration': [
        'deploy', 'deployment', 'canary', 'migration',
        'terraform', 'wrapper', 'idempotent'
    ],
    'Governance & CI Enforcement': [
        'governance', 'branch', 'protection', 'ci', 'workflow',
        'enforce', 'validation', 'policy', 'pr', 'main', 'enforcement'
    ],
    'Documentation & Runbooks': [
        'doc', 'docs', 'runbook', 'guide', 'readme', 'documentation'
    ],
    'Monitoring, Alerts & Post-Deploy Validation': [
        'monitor', 'alert', 'prometheus', 'ingest', 'log',
        'logging', 'alerting', 'metric'
    ]
}

# Label → Milestone mapping (priority-first)
LABEL_MILESTONE_MAP = {
    'area:observability': 'Observability & Provisioning',
    'area:secrets': 'Secrets & Credential Management',
    'area:deployment': 'Deployment Automation & Migration',
    'area:governance': 'Governance & CI Enforcement',
    'area:docs': 'Documentation & Runbooks',
    'area:monitoring': 'Monitoring, Alerts & Post-Deploy Validation',
    'type:secret': 'Secrets & Credential Management',
    'type:deployment': 'Deployment Automation & Migration',
}

# Tiebreaker priority (used when multiple milestones have same score)
TIEBREAKER_ORDER = [
    'Secrets & Credential Management',
    'Governance & CI Enforcement',
    'Deployment Automation & Migration',
    'Observability & Provisioning',
    'Monitoring, Alerts & Post-Deploy Validation',
    'Documentation & Runbooks',
]

FALLBACK_MILESTONE = 'Backlog Triage'
MIN_CONFIDENCE_SCORE = 2

# === HEURISTIC FUNCTIONS ===

def pick_by_labels(labels: List[str]) -> Optional[str]:
    """
    Check labels first: if label→milestone mapping exists, use it (priority-first).
    Returns milestone name or None.
    """
    for label in labels:
        label_lower = label.lower()
        if label_lower in LABEL_MILESTONE_MAP:
            return LABEL_MILESTONE_MAP[label_lower]
    return None


def pick_by_keywords(text: str, min_score: int = MIN_CONFIDENCE_SCORE) -> Optional[Tuple[str, int]]:
    """
    Keyword-based scoring: count keyword matches per milestone.
    Returns (milestone, score) or (None, score) if confidence too low.
    """
    text_lower = (text or '').lower()
    scores = {}
    
    for milestone, keywords in MILESTONE_GROUPS.items():
        score = sum(1 for kw in keywords if kw in text_lower)
        scores[milestone] = score
    
    best_score = max((s for s in scores.values()), default=0)
    
    # Confidence check
    if best_score < min_score:
        return None, best_score
    
    # Find candidates with best score
    candidates = [m for m, s in scores.items() if s == best_score]
    
    # Tiebreak if multiple candidates
    if len(candidates) > 1:
        best_milestone = next((m for m in TIEBREAKER_ORDER if m in candidates), candidates[0])
    else:
        best_milestone = candidates[0]
    
    return best_milestone, best_score


def pick(title_body: str, labels: List[str], min_score: int = MIN_CONFIDENCE_SCORE) -> Tuple[Optional[str], Optional[int]]:
    """
    Combined heuristic: labels first, then keywords.
    
    Returns:
        (milestone_name, confidence_score) where score is None if label-based
    """
    # Label-first routing
    label_milestone = pick_by_labels(labels)
    if label_milestone:
        return label_milestone, None  # Label-based has implicit high confidence
    
    # Keyword-based scoring
    return pick_by_keywords(title_body, min_score)


def classify_issues(
    issues: List[Dict],
    min_score: int = MIN_CONFIDENCE_SCORE,
    reassign_unconfident: bool = False
) -> Tuple[Dict[str, List], List]:
    """
    Classify a list of GitHub issues by milestone.
    
    Args:
        issues: List of issue dicts with: {number, title, body, labels, milestone}
        min_score: Minimum keyword score for assignment (default 2)
        reassign_unconfident: If True, re-assign even if already has milestone
    
    Returns:
        (plan, unassigned) where:
        - plan: Dict[milestone] = [(issue_num, score), ...]
        - unassigned: List of issue numbers with low confidence
    """
    plan = {m: [] for m in MILESTONE_GROUPS}
    plan[FALLBACK_MILESTONE] = []
    unassigned = []
    
    for issue in issues:
        # Skip already-assigned issues (unless reassigning)
        if issue.get('milestone') and not reassign_unconfident:
            continue
        
        number = issue['number']
        title = issue.get('title') or ''
        body = issue.get('body') or ''
        text = title + '\n' + body
        
        labels = [l['name'] if isinstance(l, dict) else l for l in issue.get('labels', [])]
        
        # Classify
        milestone, score = pick(text, labels, min_score)
        
        if milestone:
            plan[milestone].append((number, score or 0))
        else:
            unassigned.append((number, score or 0))
    
    return plan, unassigned


def audit_log_entry(issue_number: int, milestone: str, status: str = 'assigned', score: Optional[int] = None) -> Dict:
    """Generate audit log entry (JSONL compatible)."""
    entry = {
        'timestamp': __import__('datetime').datetime.utcnow().isoformat() + 'Z',
        'event': 'milestone_assignment',
        'issue': issue_number,
        'milestone': milestone,
        'status': status,
    }
    if score is not None:
        entry['confidence_score'] = score
    return entry


def main_preview(issues_json: str, min_score: int = MIN_CONFIDENCE_SCORE):
    """Preview mode: show assignment plan without executing."""
    issues = json.loads(issues_json)
    plan, unassigned = classify_issues(issues, min_score)
    
    print("=== PREVIEW: Planned Assignments ===")
    for milestone, assignments in plan.items():
        print(f"{milestone}: {len(assignments)}")
        if assignments and len(assignments) <= 10:
            for num, score in assignments:
                print(f"  - #{num} (confidence: {score})")
    
    print(f"\nUnassigned (low confidence): {len(unassigned)}")
    if unassigned:
        for num, score in unassigned[:10]:
            print(f"  - #{num} (score: {score} < {min_score})")
    
    return plan, unassigned


def main_classify(issues_json: str, min_score: int = MIN_CONFIDENCE_SCORE) -> Dict:
    """Return classification plan as JSON."""
    issues = json.loads(issues_json)
    plan, unassigned = classify_issues(issues, min_score)
    
    result = {}
    for milestone, assignments in plan.items():
        result[milestone] = [{'number': num, 'score': score} for num, score in assignments]
    
    result['unassigned'] = [{'number': num, 'score': score} for num, score in unassigned]
    
    return result


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: milestone_heuristic_v2.py <mode> [--min-score N] [--reassign-unconfident]")
        print("  mode: classify (JSON output) | preview (human readable)")
        sys.exit(1)
    
    mode = sys.argv[1]
    min_score = MIN_CONFIDENCE_SCORE
    reassign = False
    
    # Parse options
    for arg in sys.argv[2:]:
        if arg.startswith('--min-score='):
            min_score = int(arg.split('=')[1])
        elif arg == '--reassign-unconfident':
            reassign = True
    
    # Read issues from stdin
    issues_json = sys.stdin.read()
    
    if mode == 'classify':
        result = main_classify(issues_json, min_score)
        print(json.dumps(result, indent=2))
    elif mode == 'preview':
        main_preview(issues_json, min_score)
    else:
        print(f"Unknown mode: {mode}")
        sys.exit(1)
