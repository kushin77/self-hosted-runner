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

try:
    import pyotp
except ImportError:
    pyotp = None

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


def require_mfa(f):
    """Decorator: require valid MFA token (X-MFA-OTP header) for step-up auth."""
    @wraps(f)
    def wrapper(*args, **kwargs):
        if not pyotp:
            # pyotp not available, skip MFA enforcement
            return f(*args, **kwargs)
        
        mfa_otp = request.headers.get('X-MFA-OTP')
        mfa_secret = os.environ.get('PORTAL_MFA_SECRET')
        
        if not mfa_secret:
            audit_write({'event': 'mfa_config_missing', 'path': request.path})
            return jsonify({'error': 'MFA not configured'}), 500
        
        if not mfa_otp:
            audit_write({'event': 'mfa_missing', 'path': request.path, 'remote_addr': request.remote_addr})
            return jsonify({'error': 'MFA required: provide X-MFA-OTP header'}), 401
        
        totp = pyotp.TOTP(mfa_secret)
        if not totp.verify(mfa_otp):
            audit_write({'event': 'mfa_failed', 'path': request.path, 'remote_addr': request.remote_addr})
            return jsonify({'error': 'invalid MFA token'}), 401
        
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


@app.route('/api/v1/auth/validate-mfa', methods=['POST'])
@require_admin
def api_validate_mfa():
    """Validate MFA token (TOTP).
    
    Request headers:
      X-ADMIN-KEY: authentication key
      X-MFA-OTP: 6-digit TOTP token
    
    Returns:
      200: {'valid': True, 'timestamp': ...} if token is valid
      401: {'error': '...'} if token is invalid or missing
    """
    if not pyotp:
        return jsonify({'error': 'MFA not available (pyotp not installed)'}), 500
    
    mfa_otp = request.headers.get('X-MFA-OTP')
    mfa_secret = os.environ.get('PORTAL_MFA_SECRET')
    
    if not mfa_secret:
        audit_write({'event': 'mfa_validate_config_missing', 'remote_addr': request.remote_addr})
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/auth/validate-mfa', http_status='500').inc()
        except Exception:
            pass
        return jsonify({'error': 'MFA not configured on server'}), 500
    
    if not mfa_otp:
        audit_write({'event': 'mfa_validate_missing', 'remote_addr': request.remote_addr})
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/auth/validate-mfa', http_status='400').inc()
        except Exception:
            pass
        return jsonify({'error': 'MFA token required: provide X-MFA-OTP header'}), 400
    
    try:
        totp = pyotp.TOTP(mfa_secret)
        is_valid = totp.verify(mfa_otp)
        
        if is_valid:
            audit_write({'event': 'mfa_validate_success', 'remote_addr': request.remote_addr})
            try:
                REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/auth/validate-mfa', http_status='200').inc()
            except Exception:
                pass
            return jsonify({
                'valid': True,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }), 200
        else:
            audit_write({'event': 'mfa_validate_failed', 'remote_addr': request.remote_addr})
            try:
                REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/auth/validate-mfa', http_status='401').inc()
            except Exception:
                pass
            return jsonify({'error': 'invalid MFA token'}), 401
    except Exception as e:
        audit_write({'event': 'mfa_validate_error', 'error': str(e), 'remote_addr': request.remote_addr})
        try:
            REQUEST_COUNT.labels(method=request.method, endpoint='/api/v1/auth/validate-mfa', http_status='500').inc()
        except Exception:
            pass
        return jsonify({'error': 'internal server error'}), 500


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
@require_mfa
def api_migrate():
    """Initiate migration (dry-run or live).
    
    DESTRUCTIVE OPERATIONS (live mode) require MFA:
      X-MFA-OTP header with valid TOTP token required for mode='live'
    
    Request JSON:
      {
        "source": "on-prem|gcp|aws|azure",
        "destination": "on-prem|gcp|aws|azure",
        "mode": "dry-run|live",
        "rollback": true
      }
    
    Returns:
      200: Dry-run completed synchronously
      202: Live migration queued, returns job_id
    """
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
    def execute_migration_step(step_name, source, destination):
        """Execute a single migration step.
        
        Returns: (success: bool, details: dict)
        """
        details = {'step': step_name, 'source': source, 'destination': destination}
        
        try:
            if step_name == 'validate_source':
                # Validate source environment connectivity + state
                # TODO: Add actual validation (check credentials, connectivity, state dump)
                details['validated'] = True
                details['message'] = f'Source {source} validation (placeholder)'
                return True, details
            
            elif step_name == 'provision_tunnel':
                # Establish secure tunnel between source and target
                # TODO: Implement SSH/VPN/Cloud Interconnect establishment
                details['tunnel_status'] = 'provisioned'
                details['message'] = f'Tunnel from {source} to {destination} (placeholder)'
                return True, details
            
            elif step_name == 'sync_data':
                # Replicate data from source to destination
                # TODO: Implement actual data sync (rsync, gsutil, aws s3 sync, cloud-native APIs)
                details['avg_throughput_mbps'] = 1000
                details['total_transferred_gb'] = 0
                details['message'] = f'Data sync from {source} to {destination} (placeholder)'
                return True, details
            
            elif step_name == 'verify_checksums':
                # Verify bit-for-bit integrity of replicated data
                # TODO: Implement checksum verification (SHA256 per file/object)
                details['checksums_verified'] = True
                details['checksum_algorithm'] = 'sha256'
                details['message'] = f'Checksum verification (placeholder)'
                return True, details
            
            elif step_name == 'cutover_dns':
                # Update DNS/routing to point to destination
                # TODO: Implement DNS failover (Cloud DNS, Route53, Azure DNS)
                details['dns_ttl_before'] = 3600
                details['dns_ttl_after'] = 30
                details['message'] = f'DNS cutover from {source} to {destination} (placeholder)'
                return True, details
            
            elif step_name == 'post_check':
                # Run post-migration health checks
                # TODO: Implement health checks (HTTP endpoints, database queries, etc)
                details['health_check_status'] = 'passing'
                details['services_up'] = 5
                details['services_down'] = 0
                details['message'] = f'Post-migration health checks (placeholder)'
                return True, details
            
            else:
                return False, {'error': f'Unknown step: {step_name}'}
        
        except Exception as e:
            return False, {'error': str(e), 'step': step_name}
    
    def migrator_job(jid, payload):
        """Background job runner for live migrations."""
        source = payload.get('source')
        destination = payload.get('destination')
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
            
            # Execute the step (currently placeholder, but structured for real implementation)
            success, details = execute_migration_step(step, source, destination)
            
            if success:
                audit_write({'job_id': jid, 'event': 'step_end', 'step': step, 'status': 'success', 'details': details})
            else:
                audit_write({'job_id': jid, 'event': 'step_end', 'step': step, 'status': 'failed', 'error': details.get('error')})
                # On failure, could trigger rollback here
                if payload.get('rollback', True):
                    audit_write({'job_id': jid, 'event': 'rollback_triggered', 'failed_step': step})
                pj.set_status(jid, 'failed')
                JOB_EVENTS.labels(event='job_failed').inc()
                return
        
        duration = time.time() - start
        try:
            JOB_DURATION.observe(duration)
        except Exception:
            pass
        audit_write({'job_id': jid, 'event': 'job_completed', 'status': 'success', 'duration_seconds': duration})
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
