import os
import hmac
import hashlib
import tempfile
import uuid
import json
import logging
from flask import Flask, request, abort, jsonify
import requests
from google.cloud import storage
from googleapiclient import discovery
import google.auth
import time

logging.basicConfig(level=logging.INFO)
app = Flask(__name__)

GCS_BUCKET = os.environ.get("GCS_BUCKET", "nexusshield-prod-phase1-audit")
PROJECT = os.environ.get("PROJECT", "nexusshield-prod")
REPO_OWNER = os.environ.get("REPO_OWNER", "kushin77")
REPO_NAME = os.environ.get("REPO_NAME", "self-hosted-runner")
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET")

# Health check endpoints for Cloud Run
@app.route('/health', methods=['GET'])
def health_check():
    """Readiness and liveness probe endpoint."""
    return jsonify({"status": "ok", "service": "nexus-webhook"}), 200

@app.route('/health/ready', methods=['GET'])
def readiness_probe():
    """Kubernetes readiness probe."""
    try:
        # Quick check that we can access GCS
        storage_client = storage.Client()
        storage_client.list_buckets()
        return jsonify({"ready": True}), 200
    except Exception as e:
        logging.warning("Readiness check failed: %s", e)
        return jsonify({"ready": False, "error": str(e)}), 503

@app.route('/health/live', methods=['GET'])
def liveness_probe():
    """Kubernetes liveness probe."""
    return jsonify({"alive": True}), 200

@app.route('/', methods=['GET'])
def index():
    """Default route."""
    return jsonify({"service": "nexus-webhook", "version": "1.0.0"}), 200

@app.route('/', methods=['POST'])
def receive():
    payload = request.get_data()
    if WEBHOOK_SECRET:
        sig = request.headers.get('X-Hub-Signature-256')
        if not sig:
            logging.warning('Missing signature header')
            abort(400)
        mac = hmac.new(WEBHOOK_SECRET.encode(), payload, hashlib.sha256)
        expected = 'sha256=' + mac.hexdigest()
        if not hmac.compare_digest(expected, sig):
            logging.warning('Invalid signature')
            abort(403)

    event = request.headers.get('X-GitHub-Event', 'unknown')
    data = request.get_json(silent=True) or {}
    logging.info('Received event %s', event)

    if event == 'push':
        ref = data.get('ref', '')
        if ref.endswith('/main') or ref == 'refs/heads/main':
            ref_name = data.get('after', 'main')
            commit_sha = data.get('after')
            tar_url = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/tarball/{ref_name}"
            token = os.environ.get('GITHUB_TOKEN')
            headers = {'Accept': 'application/vnd.github.v3+json'}
            if token:
                headers['Authorization'] = f'token {token}'

            def post_github_status(sha, state, description, target_url=None, context='policy-check'):
                if not token or not sha:
                    return
                status_url = f"https://api.github.com/repos/{REPO_OWNER}/{REPO_NAME}/statuses/{sha}"
                body = {'state': state, 'description': description, 'context': context}
                if target_url:
                    body['target_url'] = target_url
                try:
                    requests.post(status_url, headers=headers, json=body, timeout=10)
                except Exception:
                    logging.exception('Failed posting status to GitHub')

            r = requests.get(tar_url, headers=headers, stream=True, timeout=60)
            if r.status_code != 200:
                logging.error('Failed to download tarball: %s', r.status_code)
                return jsonify({'error': 'download_failed', 'status': r.status_code}), 502

            fname = f"{uuid.uuid4()}.tgz"
            tmpf = tempfile.NamedTemporaryFile(delete=False)
            for chunk in r.iter_content(chunk_size=8192):
                if chunk:
                    tmpf.write(chunk)
            tmpf.flush()
            tmpf.close()

            storage_client = storage.Client()
            bucket = storage_client.bucket(GCS_BUCKET)
            blob = bucket.blob(fname)
            blob.upload_from_filename(tmpf.name)
            gcs_obj = f"gs://{GCS_BUCKET}/{fname}"
            logging.info('Uploaded source to %s', gcs_obj)

            credentials, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
            cb = discovery.build('cloudbuild', 'v1', credentials=credentials, cache_discovery=False)

            # mark commit as pending for CI
            if commit_sha and token:
                post_github_status(commit_sha, 'pending', 'policy-check: build started', context='policy-check')

            build_body = {
                'projectId': PROJECT,
                'source': {
                    'storageSource': {
                        'bucket': GCS_BUCKET,
                        'object': fname
                    }
                },
                'steps': [
                    {'name': 'python:3.11-slim', 'entrypoint': 'bash', 'args': ['-c', 'python -m pip install --upgrade pip setuptools wheel && pip install pytest pytest-asyncio httpx flask']},
                    {'name': 'python:3.11-slim', 'entrypoint': 'bash', 'args': ['-c', 'cat > /tmp/mock_server.py <<\'PY\'\nfrom flask import Flask, jsonify, request\napp=Flask(__name__)\n@app.route("/health")\ndef h():\n    return jsonify({"ok": True})\nif __name__=="__main__":\n    app.run(host="0.0.0.0", port=8080)\nPY\npython /tmp/mock_server.py & sleep 1 & pytest -q tests/e2e_test_framework.py::test_happy_path -k test_happy_path -s --maxfail=1']},
                ],
                'timeout': '1200s'
            }

            resp = cb.projects().builds().create(projectId=PROJECT, body=build_body).execute()
            build_id = resp.get('metadata', {}).get('build', {}).get('id') or resp.get('id')
            logging.info('Started build: %s', build_id)

            # poll build status
            if build_id:
                status = 'QUEUED'
                try:
                    while True:
                        b = cb.projects().builds().get(projectId=PROJECT, id=build_id).execute()
                        status = b.get('status')
                        logging.info('Build %s status=%s', build_id, status)
                        if status in ('SUCCESS', 'FAILURE', 'INTERNAL_ERROR', 'CANCELLED', 'TIMEOUT'):
                            break
                        time.sleep(5)
                except Exception:
                    logging.exception('Error polling build status')

                # post final status to GitHub
                if commit_sha and token:
                    if status == 'SUCCESS':
                        post_github_status(commit_sha, 'success', 'policy-check: passed', target_url='', context='policy-check')
                    else:
                        post_github_status(commit_sha, 'failure', f'policy-check: {status}', target_url='', context='policy-check')

            return jsonify({'started': True, 'build_id': build_id, 'status': status}), 202

    return jsonify({'handled': False}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
