#!/usr/bin/env python3
"""Offline milestone heuristic mapping used by local tests.

Reads a JSON array of issues and prints a mapping issue -> milestone.
"""
import json
import sys

groups={
 'Observability & Provisioning':['observab','provision','agent','filebeat','node_exporter','vault-agent','provisioning'],
 'Secrets & Credential Management':['secret','secrets','aws','secretsmanager','gsm','vault','kms','credential','gitleaks','secrets found','rotate'],
 'Deployment Automation & Migration':['deploy','deployment','canary','migration','terraform','wrapper','idempotent','terraform'],
 'Governance & CI Enforcement':['governance','branch','protection','ci','workflow','enforce','validation','policy','pr','main','enforcement'],
 'Documentation & Runbooks':['doc','docs','runbook','guide','readme','documentation'],
 'Monitoring, Alerts & Post-Deploy Validation':['monitor','alert','prometheus','ingest','log','logging','alerting','metric']
}

def pick(text, labels=None, min_score=2):
    """
    Heuristic pick.
    - If `labels` is None: legacy mode, return milestone string (or None).
    - If `labels` provided: return (milestone_or_none, score).
    """
    legacy = (labels is None)
    labels = labels or []
    t = (text or '').lower()
    # label-first mapping
    label_map = {
        'area:observability':'Observability & Provisioning',
        'area:secrets':'Secrets & Credential Management',
        'area:deployment':'Deployment Automation & Migration',
        'area:governance':'Governance & CI Enforcement',
        'area:docs':'Documentation & Runbooks',
        'area:monitoring':'Monitoring, Alerts & Post-Deploy Validation'
    }
    for L in labels:
        if L.lower() in label_map:
            if legacy:
                return label_map[L.lower()]
            return label_map[L.lower()], 999

    best = None
    bestscore = 0
    for g, keys in groups.items():
        score = sum(1 for k in keys if k in t)
        if score > bestscore:
            best = g; bestscore = score

    if legacy:
        return best
    if bestscore < min_score:
        return None, bestscore
    return best, bestscore

def main(path):
    issues=json.load(open(path))
    assignments=[]
    for i in issues:
        if i.get('milestone'):
            continue
        text=(i.get('title') or '')+'\n'+(i.get('body') or '')
        g=pick(text)
        target=g if g else 'All Untriaged'
        assignments.append({'issue':i.get('number'),'milestone':target})
    print(json.dumps(assignments,indent=2))

if __name__=='__main__':
    if len(sys.argv)<2:
        print('usage: milestone_heuristic.py <fixture.json>')
        sys.exit(2)
    main(sys.argv[1])
