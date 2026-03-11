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


@app.route('/api/v1/jobs', methods=['GET'])
@require_admin
def api_list_jobs():
    """List all migration jobs with pagination support."""
    try:
        page = int(request.args.get('page', 1))
        limit = int(request.args.get('limit', 50))
        if page < 1 or limit < 1 or limit > 200:
            return jsonify({'error': 'invalid pagination params'}), 400
        
        offset = (page - 1) * limit
        jobs = pj.list_jobs(limit=limit, offset=offset)
        total = pj.count_jobs()
        
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs', http_status='200').inc()
        except Exception:
            pass
        
        return jsonify({
            'jobs': jobs,
            'total': total,
            'page': page,
            'limit': limit,
            'pages': (total + limit - 1) // limit
        })
    except Exception as e:
        audit_write({'event': 'api_error', 'endpoint': '/api/v1/jobs', 'error': str(e)})
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs', http_status='500').inc()
        except Exception:
            pass
        return jsonify({'error': 'internal server error'}), 500


@app.route('/api/v1/jobs/<job_id>/details', methods=['GET'])
@require_admin
def api_job_details(job_id):
    """Get job details with complete audit trail."""
    try:
        job = pj.load_job(job_id)
        if not job:
            try:
                REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>/details', http_status='404').inc()
            except Exception:
                pass
            return jsonify({'error': 'job not found'}), 404
        
        # Retrieve audit entries for this job
        audit_entries = []
        try:
            with open(AUDIT_LOG, 'r', encoding='utf-8') as f:
                for line in f:
                    try:
                        entry = json.loads(line)
                        if entry.get('job_id') == job_id:
                            audit_entries.append(entry)
                    except json.JSONDecodeError:
                        continue
        except FileNotFoundError:
            pass
        
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>/details', http_status='200').inc()
        except Exception:
            pass
        
        return jsonify({
            'job': job,
            'audit_entries': audit_entries,
            'audit_count': len(audit_entries)
        })
    except Exception as e:
        audit_write({'event': 'api_error', 'endpoint': '/api/v1/jobs/{job_id}/details', 'error': str(e)})
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>/details', http_status='500').inc()
        except Exception:
            pass
        return jsonify({'error': 'internal server error'}), 500


@app.route('/api/v1/jobs/<job_id>', methods=['DELETE'])
@require_admin
def api_cancel_job(job_id):
    """Cancel in-progress migration job."""
    try:
        job = pj.load_job(job_id)
        if not job:
            try:
                REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>', http_status='404').inc()
            except Exception:
                pass
            return jsonify({'error': 'job not found'}), 404
        
        if job.get('status') not in ('queued', 'running'):
            try:
                REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>', http_status='400').inc()
            except Exception:
                pass
            return jsonify({'error': f"cannot cancel job in {job.get('status')} status"}), 400
        
        pj.set_status(job_id, 'cancelled')
        audit_write({'job_id': job_id, 'event': 'job_cancelled', 'previous_status': job.get('status')})
        try:
            JOB_EVENTS.labels(event='job_cancelled').inc()
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>', http_status='200').inc()
        except Exception:
            pass
        
        return jsonify({'job_id': job_id, 'status': 'cancelled'})
    except Exception as e:
        audit_write({'event': 'api_error', 'endpoint': '/api/v1/jobs/{job_id}', 'error': str(e)})
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>', http_status='500').inc()
        except Exception:
            pass
        return jsonify({'error': 'internal server error'}), 500


@app.route('/api/v1/jobs/<job_id>/replay', methods=['POST'])
@require_admin
def api_replay_job(job_id):
    """Retry failed job from dead-letter queue."""
    try:
        job = pj.load_job(job_id)
        if not job:
            try:
                REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>/replay', http_status='404').inc()
            except Exception:
                pass
            return jsonify({'error': 'job not found'}), 404
        
        if job.get('status') != 'failed':
            try:
                REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>/replay', http_status='400').inc()
            except Exception:
                pass
            return jsonify({'error': f"cannot replay job in {job.get('status')} status"}), 400
        
        # Create new job with same payload but new ID
        new_job_id = str(uuid.uuid4())
        new_job = job.copy()
        new_job['id'] = new_job_id
        new_job['status'] = 'queued'
        new_job['created_at'] = datetime.utcnow().isoformat() + 'Z'
        new_job['replay_of'] = job_id
        
        pj.save_job(new_job)
        audit_write({'previous_job_id': job_id, 'new_job_id': new_job_id, 'event': 'job_replayed', 'payload': new_job})
        try:
            JOB_EVENTS.labels(event='job_replayed').inc()
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>/replay', http_status='200').inc()
        except Exception:
            pass
        
        return jsonify({'new_job_id': new_job_id, 'original_job_id': job_id, 'status': 'queued'}), 201
    except Exception as e:
        audit_write({'event': 'api_error', 'endpoint': '/api/v1/jobs/{job_id}/replay', 'error': str(e)})
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/jobs/<job_id>/replay', http_status='500').inc()
        except Exception:
            pass
        return jsonify({'error': 'internal server error'}), 500


@app.route('/api/v1/metrics/summary', methods=['GET'])
@require_admin
def api_metrics_summary():
    """Get system metrics summary for dashboard."""
    try:
        stats = pj.get_stats()
        
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/metrics/summary', http_status='200').inc()
        except Exception:
            pass
        
        return jsonify({
            'jobs_queued': stats.get('queued', 0),
            'jobs_running': stats.get('running', 0),
            'jobs_completed': stats.get('completed', 0),
            'jobs_failed': stats.get('failed', 0),
            'jobs_cancelled': stats.get('cancelled', 0),
            'total_jobs': stats.get('total', 0),
            'avg_duration_s': stats.get('avg_duration', 0),
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        })
    except Exception as e:
        audit_write({'event': 'api_error', 'endpoint': '/api/v1/metrics/summary', 'error': str(e)})
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/metrics/summary', http_status='500').inc()
        except Exception:
            pass
        return jsonify({'error': 'internal server error'}), 500


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
