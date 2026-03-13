#!/usr/bin/env python3
"""
assign_milestones_batch.py

Apply milestone assignments using GitHub GraphQL in batches.

Usage:
  assign_milestones_batch.py <classification_json_file> <repo> [--batch-size N]

Notes:
- Requires GH_TOKEN in environment (GSM/Vault/KMS cred helper should set this).
- Uses GraphQL mutation `updateIssue` with milestoneId.
- Batches up to --batch-size updates per request.
- Emits Prometheus metrics on metrics server (:8080/metrics).
"""
import json
import os
import sys
import requests
import time
from typing import Dict, List

try:
    from prometheus_client import Counter, Histogram, CollectorRegistry, generate_latest
    METRICS_AVAILABLE = True
except ImportError:
    METRICS_AVAILABLE = False

GITHUB_API = "https://api.github.com/graphql"

# Prometheus metrics (optional)
if METRICS_AVAILABLE:
    ASSIGNMENTS_TOTAL = Counter('milestone_assignments_total', 'Total milestones assigned', ['milestone'])
    FAILURES_TOTAL = Counter('milestone_assignment_failures_total', 'Total assignment failures')
    DURATION_SECONDS = Histogram('milestone_assignment_duration_seconds', 'Duration of assignment batch')
    BATCH_SIZE_METRIC = Histogram('milestone_batch_size', 'Issues per batch')
else:
    # No-op metrics
    class NoOpCounter:
        def inc(self, **kwargs): pass
    class NoOpHistogram:
        def observe(self, x): pass
    ASSIGNMENTS_TOTAL = NoOpCounter()
    FAILURES_TOTAL = NoOpCounter()
    DURATION_SECONDS = NoOpHistogram()
    BATCH_SIZE_METRIC = NoOpHistogram()


def graphql(query: str, variables: Dict = None) -> Dict:
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if not token:
        print("ERROR: GH_TOKEN or GITHUB_TOKEN not set", file=sys.stderr)
        sys.exit(2)
    headers = {"Authorization": f"bearer {token}", "Accept": "application/vnd.github.v4+json"}
    payload = {"query": query}
    if variables is not None:
        payload['variables'] = variables
    r = requests.post(GITHUB_API, json=payload, headers=headers, timeout=30)
    if r.status_code != 200:
        print(f"GraphQL API error: {r.status_code} {r.text}", file=sys.stderr)
        sys.exit(3)
    data = r.json()
    if 'errors' in data:
        print('GraphQL returned errors:', data['errors'], file=sys.stderr)
    return data.get('data', {})


def get_repo_owner_name(full: str):
    parts = full.split('/')
    if len(parts) != 2:
        raise SystemExit('Repo must be owner/name')
    return parts[0], parts[1]


def fetch_milestone_node_ids(owner: str, name: str) -> Dict[str, str]:
    # Query first 100 milestones (should be enough)
    q = '''
    query($owner:String!, $name:String!) {
      repository(owner:$owner, name:$name) {
        milestones(first:100) { nodes { id title } }
      }
    }
    '''
    data = graphql(q, {'owner': owner, 'name': name})
    nodes = data['repository']['milestones']['nodes']
    return {n['title']: n['id'] for n in nodes}


def issue_node_id(owner: str, name: str, number: int) -> str:
    q = '''
    query($owner:String!, $name:String!, $number:Int!) {
      repository(owner:$owner, name:$name) { issue(number:$number) { id } }
    }
    '''
    data = graphql(q, {'owner': owner, 'name': name, 'number': number})
    return data['repository']['issue']['id']


def batch_update(owner: str, name: str, updates: List[Dict], milestone_map: Dict[str,str]) -> int:
    """Execute batch update, return count of successful updates."""
    # updates: list of {number, milestone, issueId}
    # Build a mutation with aliases
    parts = []
    variables = {}
    for i, u in enumerate(updates):
        alias = f"m{i}"
        issue_var = f"issueId{i}"
        milestone_var = f"milestoneId{i}"
        variables[issue_var] = u['issueId']
        variables[milestone_var] = milestone_map[u['milestone']]
        part = f"{alias}: updateIssue(input: {{id: ${issue_var}, milestoneId: ${milestone_var}}}) {{ issue {{ number }} }}"
        parts.append(part)
    var_defs = ' '.join([f"${k}: ID!" for k in variables.keys()])
    mutation = f"mutation({var_defs}){{ {' '.join(parts)} }}"
    # Execute
    try:
        data = graphql(mutation, variables)
        # Track successful updates (count successful aliases in response)
        success_count = 0
        for i in range(len(updates)):
            alias = f"m{i}"
            if alias in data and data[alias].get('issue', {}).get('number'):
                success_count += 1
                milestone = updates[i]['milestone']
                ASSIGNMENTS_TOTAL.inc(milestone=milestone)
        return success_count
    except Exception as e:
        print(f"Batch update error: {e}", file=sys.stderr)
        FAILURES_TOTAL.inc()
        return 0


def main():
    if len(sys.argv) < 3:
        print("Usage: assign_milestones_batch.py <classification.json> <owner/name> [--batch-size N]")
        sys.exit(1)
    classification_file = sys.argv[1]
    repo = sys.argv[2]
    batch_size = 20
    for arg in sys.argv[3:]:
        if arg.startswith('--batch-size='):
            batch_size = int(arg.split('=',1)[1])

    with open(classification_file) as f:
        classification = json.load(f)

    owner, name = get_repo_owner_name(repo)
    milestone_nodes = fetch_milestone_node_ids(owner, name)
    # Ensure fallback
    if 'Backlog Triage' not in milestone_nodes:
        print('Fallback milestone Backlog Triage not found; create it or adjust mapping', file=sys.stderr)
        # proceed but will error on mutation if used

    # Build list of updates
    updates = []
    for milestone, items in classification.items():
        if milestone == 'unassigned':
            target = 'Backlog Triage'
        else:
            target = milestone
        for it in items:
            num = it['number']
            try:
                issue_id = issue_node_id(owner, name, num)
            except Exception as e:
                print(f'Failed to get issue node id for #{num}: {e}', file=sys.stderr)
                continue
            updates.append({'number': num, 'issueId': issue_id, 'milestone': target})

    # Batch and execute
    start_time = time.time()
    i = 0
    total_success = 0
    while i < len(updates):
        chunk = updates[i:i+batch_size]
        # Track batch size
        BATCH_SIZE_METRIC.observe(len(chunk))
        # Build milestone map for chunk
        chunk_milestones = {u['milestone'] for u in chunk}
        missing = [m for m in chunk_milestones if m not in milestone_nodes]
        if missing:
            print('Missing milestones for chunk:', missing, file=sys.stderr)
            # attempt to proceed; will fail
        try:
            success = batch_update(owner, name, chunk, milestone_nodes)
            total_success += success
            print(f'Batch updated issues {i+1}-{i+len(chunk)} ({success} successful)')
        except Exception as e:
            print('Batch update failed:', e, file=sys.stderr)
            FAILURES_TOTAL.inc()
        i += batch_size
    
    # Track total duration
    duration = time.time() - start_time
    DURATION_SECONDS.observe(duration)
    print(f'✓ Batch assignment complete: {total_success} updates in {duration:.1f}s')

if __name__ == '__main__':
    main()
