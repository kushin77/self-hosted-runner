#!/usr/bin/env bash
set -euo pipefail

# SLA monitor for GitLab issues
# Requires: PROJECT_ID or CI_PROJECT_ID, GITLAB_TOKEN, optional SLA config via env

PROJECT_ID="${PROJECT_ID:-${CI_PROJECT_ID:-}}"
API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
TOKEN="${GITLAB_TOKEN:-}"

if [ -z "$PROJECT_ID" ]; then
  echo "PROJECT_ID or CI_PROJECT_ID is required"
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "GITLAB_TOKEN is not set; cannot interact with API"
  exit 1
fi

python3 - <<'PY'
import os, sys, json, urllib.request, urllib.parse
from datetime import datetime, timezone

API_URL = os.environ.get('GITLAB_API_URL', 'https://gitlab.com/api/v4')
PROJECT_ID = os.environ['PROJECT_ID']
TOKEN = os.environ['GITLAB_TOKEN']

def api_get(path, params=None):
    url = f"{API_URL}{path}"
    if params:
        url = url + '?' + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={'PRIVATE-TOKEN': TOKEN})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)

def api_put(path, data):
    url = f"{API_URL}{path}"
    data_bytes = json.dumps(data).encode('utf-8')
    req = urllib.request.Request(url, data=data_bytes, headers={'PRIVATE-TOKEN': TOKEN, 'Content-Type': 'application/json'}, method='PUT')
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)

def list_open_issues(page=1, per_page=100):
    return api_get(f"/projects/{PROJECT_ID}/issues", {'state': 'opened', 'per_page': per_page, 'page': page})

sla_rules = {
    'type:security': 0.5,  # days
    'type:bug': {'critical': 1, 'high': 3, 'medium': 7, 'low': 14}
}

violations = []
page = 1
while True:
    issues = list_open_issues(page=page)
    if not issues:
        break
    for issue in issues:
        labels = [l for l in issue.get('labels', [])]
        created_at = datetime.fromisoformat(issue['created_at'].replace('Z', '+00:00'))
        age_days = (datetime.now(timezone.utc) - created_at).total_seconds() / 86400.0

        sla_exceeded = False
        sla_type = None

        if 'type:security' in labels:
            if age_days > sla_rules['type:security']:
                sla_exceeded = True
                sla_type = 'security'
        elif 'type:bug' in labels:
            sev = next((l.split(':',1)[1] for l in labels if l.startswith('severity:')), 'medium')
            limit = sla_rules['type:bug'].get(sev, sla_rules['type:bug']['medium'])
            if age_days > limit:
                sla_exceeded = True
                sla_type = f'bug({sev})'

        if sla_exceeded:
            violations.append({'iid': issue['iid'], 'title': issue['title'], 'age_days': round(age_days,1), 'sla_type': sla_type, 'labels': labels})
    page += 1

print(f"Total violations: {len(violations)}")
for v in violations:
    print(f"🚨 SLA Violation: #{v['iid']} ({v['sla_type']}) - {v['age_days']}d old")
    # add labels via API
    try:
        api_put(f"/projects/{PROJECT_ID}/issues/{v['iid']}", {'labels': ','.join(list(set(v['labels'] + ['sla:breached','priority:urgent'])))})
    except Exception as e:
        print('Failed to update issue labels:', e)

if violations:
    summary = "**SLA Violations Report**\n\n"
    for v in violations[:20]:
        summary += f"- #{v['iid']}: {v['title'][:60]}... ({v['age_days']}d, {v['sla_type']})\n"
    print(summary)
PY
