from flask import Flask, request, jsonify
import subprocess
import os
import uuid
import threading
import time
import json
from datetime import datetime

# ensure local module imports work when running as a script
import sys
sys.path.insert(0, os.path.dirname(__file__))

import persistent_jobs as pj
import secret_providers as secrets
import audit_store
import run_migrator
import redis

app = Flask(__name__)

# Simple in-memory job store for demo; production should use durable queue (Pub/Sub, SQS)
JOBS_LOCK = threading.Lock()
AUDIT_LOG = os.environ.get('PORTAL_AUDIT_LOG', 'logs/portal-migrate-audit.jsonl')

def audit_write(entry: dict):
    # append entry into chained append-only audit log
    try:
        audit_store.append_entry(AUDIT_LOG, entry)
    except Exception:
        # best-effort fallback: write plain JSONL
        os.makedirs(os.path.dirname(AUDIT_LOG) or '.', exist_ok=True)
        entry.setdefault('ts', datetime.utcnow().isoformat() + 'Z')
        with open(AUDIT_LOG, 'a', encoding='utf-8') as f:
            f.write(json.dumps(entry, ensure_ascii=False) + '\n')

def require_auth(f):
    from functools import wraps
    import jwt
    import requests
        import time
        import pyotp

    @wraps(f)
    def wrapper(*args, **kwargs):
        auth = request.headers.get('Authorization')
        if not auth:
            return jsonify({'error': 'missing authorization'}), 401
        if auth.startswith('Bearer '):
            token = auth.split(' ', 1)[1]
            jwks_url = os.environ.get('OIDC_JWKS_URL')
            if jwks_url:
                try:
                    # JWKS caching with simple TTL
                    ttl = int(os.environ.get('JWKS_CACHE_TTL', '300'))
                    now = int(time.time())
                    if not hasattr(require_auth, '_jwks_cache') or require_auth._jwks_cache.get('exp', 0) < now:
                        jwks = requests.get(jwks_url, timeout=5).json()
                        require_auth._jwks_cache = {'jwks': jwks, 'exp': now + ttl}
                    else:
                        jwks = require_auth._jwks_cache['jwks']

                    public_keys = {}
                    for key in jwks.get('keys', []):
                        kid = key.get('kid')
                        public_keys[kid] = jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(key))
                    unverified = jwt.decode(token, options={"verify_signature": False})
                    kid = unverified.get('kid') or unverified.get('header', {}).get('kid')
                    key = public_keys.get(kid)
                    if not key:
                        return jsonify({'error': 'invalid token key id'}), 401
                    jwt.decode(token, key=key, algorithms=[unverified.get('alg', 'RS256')], audience=os.environ.get('OIDC_AUDIENCE'))
                except Exception as e:
                    return jsonify({'error': 'invalid token', 'detail': str(e)}), 401
            else:
                # fallback to static admin key
                admin_key = os.environ.get('PORTAL_ADMIN_KEY')
                if token != admin_key:
                    return jsonify({'error': 'invalid admin key'}), 401
        else:
            return jsonify({'error': 'unsupported auth scheme'}), 401
        return f(*args, **kwargs)
    return wrapper

def run_script(path, args=None):
    cmd = [path]
    if args:
        cmd.extend(args)
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return proc.returncode, proc.stdout

def migrator_job(job_id, payload):
    # Simulated migration steps; replace with real orchestrator calls
    steps = [
        'validate_source',
        'provision_tunnel',
        'sync_data',
        'verify_checksums',
        'cutover_dns',
        'post_check'
    ]
    audit_write({'job_id': job_id, 'event': 'job_started', 'payload': payload})
    for step in steps:
        audit_write({'job_id': job_id, 'event': 'step_start', 'step': step})
        # simulate work
        time.sleep(1)
        audit_write({'job_id': job_id, 'event': 'step_end', 'step': step, 'status': 'ok'})

    audit_write({'job_id': job_id, 'event': 'job_completed', 'status': 'success'})
    pj.set_status(job_id, 'completed')



@app.route('/', methods=['POST'])
def handler():
    payload = request.get_json(silent=True) or {}
    action = payload.get('action') or payload.get('message', {}).get('data')

    if isinstance(action, str) and action.startswith('ey'):  # base64 encoded maybe
        try:
            import base64
            decoded = base64.b64decode(action).decode('utf-8')
            import json as _json
            j = _json.loads(decoded)
            action = j.get('action', action)
        except Exception:
            pass

    if action == 'vault_sync':
        path = '/opt/scripts/sync_gsm_to_vault.sh'
        code, out = run_script(path)
        return jsonify({'action': 'vault_sync', 'exit': code, 'output': out}), (200 if code == 0 else 500)
    elif action == 'cleanup_ephemeral':
        path = '/opt/scripts/cleanup_ephemeral_runners.sh'
        # expect env PROJECT and ZONE to be set in runtime
        code, out = run_script(path)
        return jsonify({'action': 'cleanup_ephemeral', 'exit': code, 'output': out}), (200 if code == 0 else 500)
    else:
        return jsonify({'error': 'unknown action', 'received': payload}), 400


@app.route('/health', methods=['GET'])
def health():
    return 'OK', 200


@app.route('/api/v1/migrate', methods=['POST'])
def api_migrate():
    req = request.get_json(silent=True)
    if not req:
        return jsonify({'error': 'invalid json payload'}), 400

    source = req.get('source')
    destination = req.get('destination')
    mode = req.get('mode', 'dry-run')
    rollback = bool(req.get('rollback', True))

    if mode not in ('dry-run', 'live'):
        return jsonify({'error': 'mode must be dry-run or live'}), 400

    job_id = str(uuid.uuid4())
    job = {'id': job_id, 'source': source, 'destination': destination, 'mode': mode, 'rollback': rollback, 'status': 'queued', 'created_at': datetime.utcnow().isoformat() + 'Z'}
    pj.save_job(job)

    audit_write({'job_id': job_id, 'event': 'job_queued', 'payload': job})

    # Enforce MFA for live/destructive operations
    if mode == 'live':
        # Expect a TOTP in header `X-MFA-OTP` or as `mfa_otp` field in payload
        otp = request.headers.get('X-MFA-OTP') or req.get('mfa_otp')
        if not otp:
            return jsonify({'error': 'mfa required for live operations'}), 401
        # retrieve MFA secret from secret provider
        mfa_secret = secrets.get_secret('PORTAL_MFA_SECRET') or os.environ.get('PORTAL_MFA_SECRET')
        if not mfa_secret:
            return jsonify({'error': 'mfa not configured'}), 500
        try:
            if not pyotp.TOTP(mfa_secret).verify(otp, valid_window=1):
                return jsonify({'error': 'invalid mfa'}), 401
        except Exception as e:
            return jsonify({'error': 'mfa verification failed', 'detail': str(e)}), 401

    if mode == 'dry-run':
        # Synchronous dry-run simulation
        audit_write({'job_id': job_id, 'event': 'dry_run_simulation_start'})
        # Simulate validation steps quickly
        audit_write({'job_id': job_id, 'event': 'dry_run_validation', 'status': 'ok'})
        audit_write({'job_id': job_id, 'event': 'dry_run_completed'})
        pj.set_status(job_id, 'completed')
        return jsonify({'job_id': job_id, 'status': 'completed', 'mode': mode}), 200

    # For live mode, spawn background worker
    pj.set_status(job_id, 'running')
    job = pj.load_job(job_id)
    job['started_at'] = datetime.utcnow().isoformat() + 'Z'
    pj.save_job(job)
    # If REDIS_URL configured, enqueue job to Redis list for workers to process
    redis_url = os.environ.get('REDIS_URL')
    if redis_url:
        try:
            r = redis.from_url(redis_url)
            r.rpush('migration_jobs', json.dumps(job))
            audit_write({'job_id': job_id, 'event': 'enqueued', 'backend': 'redis'})
            return jsonify({'job_id': job_id, 'status': 'enqueued'}), 202
        except Exception as e:
            audit_write({'job_id': job_id, 'event': 'enqueue_failed', 'error': str(e)})

    # Fallback: run in-process worker thread
    t = threading.Thread(target=run_migrator.run_migrator, args=(job_id, job), daemon=True)
    t.start()

    return jsonify({'job_id': job_id, 'status': 'running'}), 202


@app.route('/api/v1/migrate/<job_id>', methods=['GET'])
def api_migrate_status(job_id):
    job = pj.load_job(job_id)
    if not job:
        return jsonify({'error': 'job not found'}), 404
    return jsonify(job), 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', '8080')))
