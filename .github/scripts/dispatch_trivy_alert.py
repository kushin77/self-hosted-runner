#!/usr/bin/env python3
import sys, json, os, argparse, requests

parser = argparse.ArgumentParser()
parser.add_argument('--repo', required=True)
parser.add_argument('--token', required=True)
parser.add_argument('--file', required=True)
args = parser.parse_args()

with open(args.file,'r') as f:
    report = json.load(f)

# extract image and summary
image = None
try:
    image = report.get('ArtifactName') or report.get('Target') or report.get('Artifact', {}).get('repository')
except Exception:
    image = 'unknown'

# Count critical/high
vulns = []
for r in report.get('Results',[]):
    for v in r.get('Vulnerabilities',[]) :
        vulns.append({'id': v.get('VulnerabilityID') or v.get('VulnID'), 'severity': v.get('Severity'), 'pkg': v.get('PkgName')})

critical = sum(1 for v in vulns if (v['severity'] or '').lower()=='critical')
high = sum(1 for v in vulns if (v['severity'] or '').lower()=='high')

payload = {'image': image, 'critical': critical, 'high': high, 'top_vulns': vulns[:25]}

url = f'https://api.github.com/repos/{args.repo}/dispatches'
headers = {'Authorization': f'token {args.token}','Accept':'application/vnd.github.everest-preview+json'}
resp = requests.post(url, json={'event_type':'trivy_alert','client_payload':payload}, headers=headers)
if resp.status_code >= 200 and resp.status_code < 300:
    print('dispatched')
    sys.exit(0)
print('dispatch failed', resp.status_code, resp.text)
sys.exit(2)
