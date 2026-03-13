#!/usr/bin/env python3
"""
Unit tests for milestone_heuristic_v2.py

Test coverage:
- Confidence threshold behavior
- Tie-breaking logic
- Label-based routing
- Keyword scoring
- Combined heuristic
"""

import sys
import json
sys.path.insert(0, '/home/akushnir/self-hosted-runner/scripts/utilities')

from milestone_heuristic_v2 import (
    pick_by_labels, pick_by_keywords, pick, classify_issues,
    TIEBREAKER_ORDER, MIN_CONFIDENCE_SCORE, FALLBACK_MILESTONE
)

# Test counters
PASSED = 0
FAILED = 0

def test(name: str, condition: bool, details: str = ""):
    global PASSED, FAILED
    if condition:
        print(f"✓ {name}")
        PASSED += 1
    else:
        print(f"✗ {name}: {details}")
        FAILED += 1

# ===== LABEL-BASED ROUTING TESTS =====
print("\n=== Label-Based Routing ===")

result = pick_by_labels(['area:secrets'])
test("Label routing: area:secrets", result == 'Secrets & Credential Management', f"Got {result}")

result = pick_by_labels(['area:governance', 'area:docs'])
test("Label routing: first match wins", result == 'Governance & CI Enforcement', f"Got {result}")

result = pick_by_labels(['unknown-label'])
test("Label routing: unknown label returns None", result is None, f"Got {result}")

# ===== CONFIDENCE THRESHOLD TESTS =====
print("\n=== Confidence Threshold ===")

result, score = pick_by_keywords("terraform deployment migration", min_score=2)
test("Threshold met (score>=2)", result is not None and score >= 2, f"Got {result}, score={score}")

result, score = pick_by_keywords("deploy", min_score=2)
test("Threshold not met (score=1 < min_score=2)", result is None and score == 1, f"Got {result}, score={score}")

result, score = pick_by_keywords("deploy", min_score=1)
test("Threshold met with min_score=1", result is not None and score == 1, f"Got {result}, score={score}")

# ===== TIE-BREAKING TESTS =====
print("\n=== Tie-Breaking Logic ===")

# Scenario: "terraform" + "policy" matches Deployment (2x) and Governance (1x)
# Should choose Deployment due to higher score
result, score = pick_by_keywords("terraform deployment policy")
test("Obvious winner (no tie)", result == 'Deployment Automation & Migration', f"Got {result}")

# Scenario: Word matches 2 categories equally
# "rotate" matches Secrets (1x), should pick it
result, score = pick_by_keywords("rotate secret management")
test("Tie-break: rotation keyword", result == 'Secrets & Credential Management', f"Got {result}")

# ===== LABEL PRIORITY TESTS =====
print("\n=== Label Priority (Labels First) ===")

# Label should take precedence over keywords
result, score = pick("This is about governance with secret keywords", ['area:docs'], min_score=1)
test("Label priority over keywords", result == 'Documentation & Runbooks', f"Got {result}")

result, score = pick("Secret management via AWS KMS vault rotation", [], min_score=1)
test("Keyword fallback (no labels)", result == 'Secrets & Credential Management', f"Got {result}")

# ===== COMBINED HEURISTIC TESTS =====
print("\n=== Combined Heuristic ===")

result, score = pick("Create deployment pipeline with canary runs", ['type:deployment'], min_score=2)
test("Type label + keyword", result == 'Deployment Automation & Migration', f"Got {result}")

result, score = pick("Branch protection enforcement policies", [], min_score=2)
test("Governance keywords (2+ match)", result == 'Governance & CI Enforcement', f"Got {result}")

result, score = pick("Random issue about stuff", [], min_score=2)
test("Low confidence returns None", result is None, f"Got {result}")

# ===== ISSUE CLASSIFICATION TESTS =====
print("\n=== Issue Classification ===")

issues = [
    {
        'number': 1,
        'title': 'Add secret rotation automation',
        'body': 'Implement GSM and Vault credential rotation',
        'labels': [],
        'milestone': None
    },
    {
        'number': 2,
        'title': 'Branch protection policy update',
        'body': 'Enforce CI validation on pull requests',
        'labels': [{'name': 'area:governance'}],
        'milestone': None
    },
    {
        'number': 3,
        'title': 'Fix typo somewhere',
        'body': 'Random text change',
        'labels': [],
        'milestone': None
    },
]

plan, unassigned = classify_issues(issues, min_score=2)

num_secrets = len(plan['Secrets & Credential Management'])
test("Classify: Issue 1 → Secrets", num_secrets > 0 and any(n == 1 for n, _ in plan['Secrets & Credential Management']), f"Got {plan['Secrets & Credential Management']}")

num_governance = len(plan['Governance & CI Enforcement'])
test("Classify: Issue 2 → Governance", num_governance > 0 and any(n == 2 for n, _ in plan['Governance & CI Enforcement']), f"Got {plan['Governance & CI Enforcement']}")

test("Classify: Issue 3 → Unassigned (low confidence)", len(unassigned) > 0 and any(n == 3 for n, _ in unassigned), f"Unassigned: {unassigned}")

# ===== ALREADY-ASSIGNED SKIP TEST =====
print("\n=== Already-Assigned Skip ===")

issues_with_milestone = [
    {
        'number': 100,
        'title': 'Already classified issue',
        'body': 'Should not be reclassified',
        'labels': [],
        'milestone': {'title': 'Some Milestone'}
    }
]

plan, unassigned = classify_issues(issues_with_milestone, min_score=2, reassign_unconfident=False)
total_assigned = sum(len(items) for items in plan.values()) + len(unassigned)
test("Skip already-assigned by default", total_assigned == 0, f"Got {total_assigned} items classified (should be 0)")

plan, unassigned = classify_issues(issues_with_milestone, min_score=2, reassign_unconfident=True)
total_assigned = sum(len(items) for items in plan.values()) + len(unassigned)
test("Reassign with --reassign-unconfident", total_assigned > 0, f"Got {total_assigned} items classified (should be >0)")

# ===== SUMMARY =====
print(f"\n=== TEST SUMMARY ===")
print(f"Passed: {PASSED}")
print(f"Failed: {FAILED}")
print(f"Total:  {PASSED + FAILED}")

if FAILED > 0:
    sys.exit(1)
else:
    print("✓ All tests passed")
    sys.exit(0)
