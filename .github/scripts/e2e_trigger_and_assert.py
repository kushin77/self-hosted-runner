#!/usr/bin/env python3
import os, sys, time, requests, json, argparse

parser = argparse.ArgumentParser()
parser.add_argument('--dry-run', action='store_true', help='Simulate dispatch and PR detection without external calls')
args = parser.parse_args()

if args.dry_run:
    print('Dry-run mode: simulating dispatch and PR detection')
    print('Simulated: dispatch sent')
    print('Simulated: found PR: https://github.com/OWNER/REPO/pull/123')
    sys.exit(0)

REPO = os.environ.get('GITHUB_REPOSITORY')
TOKEN = os.environ.get('GITHUB_TOKEN')
if not REPO or not TOKEN:
    print('GITHUB_REPOSITORY and GITHUB_TOKEN must be set in env')
    sys.exit(2)

owner, repo = REPO.split('/')
API = f'https://api.github.com/repos/{owner}/{repo}'
HEADERS = {'Authorization': f'token {TOKEN}', 'Accept': 'application/vnd.github.v3+json'}

# trigger dispatch
payload = {'event_type':'trivy_alert','client_payload':{'image':'ghcr.io/kushin77/runner:e2e-test'}}
print('Sending dispatch...')
r = requests.post(f'{API}/dispatches', headers={**HEADERS, 'Accept':'application/vnd.github.everest-preview+json'}, json=payload)
if r.status_code < 200 or r.status_code >= 300:
    print('Failed to dispatch', r.status_code, r.text)
    sys.exit(3)
print('Dispatched; polling for PR (title contains "Pin image")')

# poll for PR creation
deadline = time.time() + 600
found = None
while time.time() < deadline:
    r = requests.get(f'{API}/pulls?state=open&per_page=100', headers=HEADERS)
    if r.status_code==200:
        prs = r.json()
        for pr in prs:
            title = pr.get('title','')
            if 'Pin image' in title or 'promote image' in title or 'promote image' in pr.get('body',''):
                found = pr
                break
    if found:
        print('Found PR:', found.get('html_url'))
        sys.exit(0)
    time.sleep(10)

print('Timeout waiting for promotion PR')
sys.exit(4)
