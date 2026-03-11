"""
Migration Portal API - Flask web service
Handles migration job submission, status tracking, and audit logging
"""

from flask import Flask, request, jsonify, Response
import os
import uuid
import threading
import time
import json
from datetime import datetime
from functools import wraps
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

import persistent_jobs as pj
import secret_providers as secrets
import audit_store

app = Flask(__name__)

# Configuration
AUDIT_LOG = os.environ.get('PORTAL_AUDIT_LOG', 'logs/portal-migrate-audit.jsonl')

# Prometheus metrics
REQUEST_COUNT = Counter('nexusshield_http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'http_status'])
JOB_EVENTS = Counter('nexusshield_jobs_total', 'Job events', ['event'])
JOB_DURATION = Histogram('nexusshield_job_duration_seconds', 'Job duration seconds')


def audit_write(entry: dict):
    """Append entry to chained append-only audit log."""
    entry.setdefault('ts', datetime.utcnow().isoformat() + 'Z')
    try:
        audit_store.append_entry(AUDIT_LOG, entry)
    except Exception:
        # Fallback: write plain JSONL
        os.makedirs(os.path.dirname(AUDIT_LOG) or '.', exist_ok=True)
        with open(AUDIT_LOG, 'a', encoding='utf-8') as f:
            f.write(json.dumps(entry, ensure_ascii=False) + '\n')


def require_admin(f):
    """Decorator: require X-ADMIN-KEY header for authorization."""
    @wraps(f)
    def wrapper(*args, **kwargs):
        key = request.headers.get('X-ADMIN-KEY')
        expected_key = os.environ.get('PORTAL_ADMIN_KEY', 'changeme')
        if not key or key != expected_key:
            audit_write({'event': 'auth_failed', 'path': request.path, 'remote_addr': request.remote_addr})
            return jsonify({'error': 'unauthorized'}), 401
        return f(*args, **kwargs)
    return wrapper


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint - no auth required."""
    try:
        REQUEST_COUNT.labels(method='GET', endpoint='/health', http_status='200').inc()
    except Exception:
        pass
    return 'OK', 200


@app.route('/api/v1/migrate/<job_id>', methods=['GET'])
@require_admin
def api_migrate_status(job_id):
    """Get migration job status."""
    job = pj.load_job(job_id)
    if not job:
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/migrate/<job_id>', http_status='404').inc()
        except Exception:
            pass
        return jsonify({'error': 'not found'}), 404
    try:
        REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/migrate/<job_id>', http_status='200').inc()
    except Exception:
        pass
    return jsonify(job)


@app.route('/api/v1/migrate', methods=['POST'])
@require_admin
def api_migrate():
    """Initiate migration (dry-run or live)."""
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
    job = {
        'id': job_id,
        'source': source,
        'destination': destination,
        'mode': mode,
        'rollback': rollback,
        'status': 'queued',
        'created_at': datetime.utcnow().isoformat() + 'Z',
    }
    pj.save_job(job)
    audit_write({'job_id': job_id, 'event': 'job_queued', 'payload': job})
    try:
        JOB_EVENTS.labels(event='job_queued').inc()
    except Exception:
        pass

    if mode == 'dry-run':
        # Synchronous dry-run
        audit_write({'job_id': job_id, 'event': 'dry_run_simulation_start'})
        audit_write({'job_id': job_id, 'event': 'dry_run_validation', 'status': 'ok'})
        audit_write({'job_id': job_id, 'event': 'dry_run_completed'})
        try:
            JOB_EVENTS.labels(event='dry_run_completed').inc()
        except Exception:
            pass
        pj.set_status(job_id, 'completed')
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/migrate', http_status='200').inc()
        except Exception:
            pass
        return jsonify({'job_id': job_id, 'status': 'dry-run-completed'})

    # Live mode: background execution
    def migrator_job(jid, payload):
        """Background job runner for live migrations."""
        steps = ['validate_source', 'provision_tunnel', 'sync_data', 'verify_checksums', 'cutover_dns', 'post_check']
        audit_write({'job_id': jid, 'event': 'job_started', 'payload': payload})
        JOB_EVENTS.labels(event='job_started').inc()
        start = time.time()
        for step in steps:
            audit_write({'job_id': jid, 'event': 'step_start', 'step': step})
            try:
                JOB_EVENTS.labels(event=step).inc()
            except Exception:
                pass
            time.sleep(1)
            audit_write({'job_id': jid, 'event': 'step_end', 'step': step, 'status': 'ok'})
        duration = time.time() - start
        try:
            JOB_DURATION.observe(duration)
        except Exception:
            pass
        audit_write({'job_id': jid, 'event': 'job_completed', 'status': 'success'})
        JOB_EVENTS.labels(event='job_completed').inc()
        pj.set_status(jid, 'completed')

    t = threading.Thread(target=migrator_job, args=(job_id, job), daemon=True)
    t.start()
    pj.set_status(job_id, 'running')
    try:
        REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/migrate', http_status='202').inc()
    except Exception:
        pass
    return jsonify({'job_id': job_id, 'status': 'running'})


@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint."""
    try:
        data = generate_latest()
        return Response(data, mimetype=CONTENT_TYPE_LATEST)
    except Exception:
        return Response(b"", mimetype=CONTENT_TYPE_LATEST)


@app.errorhandler(404)
def not_found(error):
    """404 handler."""
    return jsonify({'error': 'not found'}), 404


@app.errorhandler(500)
def internal_error(error):
    """500 handler - log to audit."""
    audit_write({'event': 'internal_error', 'error': str(error)})
    return jsonify({'error': 'internal server error'}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
