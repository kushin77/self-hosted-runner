#!/usr/bin/env python3
"""Simple webhook receiver to accept portal artifacts from CI and trigger ingestion.

Usage: run with `python3 portal-sync/webhook_receiver.py` (requires Flask).
Configure `PORTAL_WEBHOOK_SECRET` to verify HMAC SHA256 signature on `X-Hub-Signature-256`.
"""
import os
import hmac
import hashlib
from flask import Flask, request, abort, jsonify
from pathlib import Path
import subprocess

APP = Flask(__name__)
ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_PATH = ROOT / 'portal-artifact.json'

SECRET = os.environ.get('PORTAL_WEBHOOK_SECRET')

def verify_signature(data, header_sig):
    if not SECRET:
        return True
    if not header_sig:
        return False
    mac = hmac.new(SECRET.encode(), msg=data, digestmod=hashlib.sha256)
    expected = 'sha256=' + mac.hexdigest()
    return hmac.compare_digest(expected, header_sig)

@APP.route('/webhook', methods=['POST'])
def webhook():
    sig = request.headers.get('X-Hub-Signature-256')
    body = request.get_data()
    if not verify_signature(body, sig):
        abort(401, 'invalid signature')

    payload = request.get_json(silent=True)
    if not payload:
        abort(400, 'invalid json')

    # Save artifact content if present
    artifact = payload.get('artifact') or payload.get('portal_artifact') or payload
    with open(ARTIFACT_PATH, 'w') as fh:
        import json
        json.dump(artifact, fh, indent=2)

    # Trigger ingestion (best-effort, run in background)
    try:
        subprocess.Popen(['python3', str(ROOT / 'portal-sync' / 'ingest_to_portal.py')])
    except Exception:
        pass

    return jsonify({'status': 'accepted'}), 202

if __name__ == '__main__':
    APP.run(host='0.0.0.0', port=int(os.environ.get('PORT', 9001)))
