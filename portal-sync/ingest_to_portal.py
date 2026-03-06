#!/usr/bin/env python3
"""Ingest `portal-artifact.json` into Portal or a local cache.

Behavior:
- If `PORTAL_URL` and `PORTAL_TOKEN` are set, POST artifact to `POST {PORTAL_URL}/api/internal/ingest-artifact`.
- Otherwise, write a copy to `portal-sync/last-ingested.json` for manual pickup.
"""
import os
import json
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / 'portal-artifact.json'
OUT = ROOT / 'portal-sync' / 'last-ingested.json'

def load_artifact():
    if not ARTIFACT.exists():
        print('artifact not found:', ARTIFACT)
        return None
    with open(ARTIFACT, 'r') as fh:
        return json.load(fh)

def push_to_portal(artifact):
    url = os.environ.get('PORTAL_URL')
    token = os.environ.get('PORTAL_TOKEN')
    if not url or not token:
        return False, 'portal credentials not set'
    dest = url.rstrip('/') + '/api/internal/ingest-artifact'
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    resp = requests.post(dest, headers=headers, json=artifact, timeout=30)
    return resp.ok, f'{resp.status_code} {resp.text[:200]}'

def main():
    art = load_artifact()
    if art is None:
        return 2

    ok, msg = push_to_portal(art)
    if ok:
        print('pushed to portal')
        with open(OUT, 'w') as fh:
            json.dump({'pushed': True, 'artifact': art}, fh, indent=2)
        return 0
    else:
        print('not pushed, storing locally:', msg)
        with open(OUT, 'w') as fh:
            json.dump({'pushed': False, 'reason': msg, 'artifact': art}, fh, indent=2)
        return 3

if __name__ == '__main__':
    raise SystemExit(main())
