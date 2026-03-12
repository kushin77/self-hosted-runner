#!/usr/bin/env python3
"""Parallel milestone assignment using the `gh` CLI.

Reads a JSON file of issues (same format as `gh issue list --json ...`) and assigns
milestones in parallel using a configurable worker pool. This is a Phase 2
improvement to reduce runtime compared to sequential `gh` calls.

Usage:
  python3 assign_milestones_parallel.py --input /path/to/issues.json --fallback "Backlog Triage" --workers 20 --reassign
"""
import argparse
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import List


def assign_issue(number: int, milestone: str) -> (int, bool, str):
    cmd = ["gh", "issue", "edit", str(number), "--milestone", milestone]
    p = subprocess.run(cmd, capture_output=True, text=True)
    ok = p.returncode == 0
    return number, ok, p.stderr.strip()


def build_assignments(issues: List[dict], min_score: int, fallback: str, reassign: bool):
    # replicate the heuristic used in organizer; simple scoring
    groups = {
        'Observability & Provisioning': ['observab','provision','agent','filebeat','node_exporter','vault-agent','provisioning'],
        'Secrets & Credential Management': ['secret','secrets','aws','secretsmanager','gsm','vault','kms','credential','gitleaks','rotate'],
        'Deployment Automation & Migration': ['deploy','deployment','canary','migration','terraform','wrapper','idempotent'],
        'Governance & CI Enforcement': ['governance','branch','protection','ci','workflow','enforce','validation','policy','pr','main','enforcement'],
        'Documentation & Runbooks': ['doc','docs','runbook','guide','readme','documentation'],
        'Monitoring, Alerts & Post-Deploy Validation': ['monitor','alert','prometheus','ingest','log','logging','alerting','metric']
    }
    label_map = {
        'area:observability': 'Observability & Provisioning',
        'area:secrets': 'Secrets & Credential Management',
        'area:deployment': 'Deployment Automation & Migration',
        'area:governance': 'Governance & CI Enforcement',
        'area:docs': 'Documentation & Runbooks',
        'area:monitoring': 'Monitoring, Alerts & Post-Deploy Validation'
    }

    assignments = []
    for i in issues:
        if i.get('milestone') and not reassign:
            continue
        num = i['number']
        text = (i.get('title') or '') + '\n' + (i.get('body') or '')
        labels = [l['name'] for l in i.get('labels', [])]
        # label-first
        chosen = None
        for L in labels:
            if L.lower() in label_map:
                chosen = label_map[L.lower()]
                break
        if not chosen:
            t = text.lower()
            scores = {g: sum(1 for k in keys if k in t) for g,keys in groups.items()}
            bestscore = max(scores.values()) if scores else 0
            if bestscore >= min_score:
                candidates = [g for g,s in scores.items() if s == bestscore]
                chosen = candidates[0]
        if not chosen:
            chosen = fallback
        assignments.append((num, chosen))
    return assignments


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--input', required=True)
    p.add_argument('--fallback', default='Backlog Triage')
    p.add_argument('--workers', type=int, default=20)
    p.add_argument('--min-score', type=int, default=2)
    p.add_argument('--reassign', action='store_true')
    args = p.parse_args()

    issues = json.load(open(args.input))
    assignments = build_assignments(issues, args.min_score, args.fallback, args.reassign)

    failures = []
    successes = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futures = {ex.submit(assign_issue, num, milestone): (num, milestone) for num,milestone in assignments}
        for fut in as_completed(futures):
            num, milestone = futures[fut]
            try:
                n, ok, err = fut.result()
                if ok:
                    successes += 1
                else:
                    failures.append({'issue': n, 'err': err})
            except Exception as e:
                failures.append({'issue': num, 'err': str(e)})

    print('Assigned', successes, 'failed', len(failures))
    if failures:
        print('Sample failures:', failures[:10])
        # create alert issue
        try:
            body = f"Parallel assign: {len(failures)} failures. Sample: {failures[:5]}"
            subprocess.run(['gh', 'issue', 'create', '--title', 'milestone-organizer: parallel assignment failures', '--body', body], check=False)
        except Exception:
            pass
        raise SystemExit(2)


if __name__ == '__main__':
    main()
