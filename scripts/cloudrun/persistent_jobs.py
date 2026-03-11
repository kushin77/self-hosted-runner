"""Simple file-backed persistent job store.
Stores job JSON files under data/jobs/ so job state survives restarts.
"""
import os
import json
from datetime import datetime

BASE_DIR = os.path.join(os.path.dirname(__file__), '..', 'data', 'jobs')
os.makedirs(BASE_DIR, exist_ok=True)

def job_path(job_id):
    return os.path.join(BASE_DIR, f"{job_id}.json")

def save_job(job):
    path = job_path(job['id'])
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(job, f, ensure_ascii=False, indent=2)

def load_job(job_id):
    path = job_path(job_id)
    if not os.path.exists(path):
        return None
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def list_jobs():
    out = []
    for fn in os.listdir(BASE_DIR):
        if fn.endswith('.json'):
            with open(os.path.join(BASE_DIR, fn), 'r', encoding='utf-8') as f:
                try:
                    out.append(json.load(f))
                except Exception:
                    continue
    return out

def set_status(job_id, status):
    job = load_job(job_id)
    if not job:
        return None
    job['status'] = status
    job['updated_at'] = datetime.utcnow().isoformat() + 'Z'
    save_job(job)
    return job

def count_jobs():
    """Count total number of jobs."""
    try:
        return len([fn for fn in os.listdir(BASE_DIR) if fn.endswith('.json')])
    except Exception:
        return 0

def list_jobs(limit=50, offset=0):
    """List jobs with pagination support."""
    try:
        all_jobs = []
        for fn in os.listdir(BASE_DIR):
            if fn.endswith('.json'):
                try:
                    with open(os.path.join(BASE_DIR, fn), 'r', encoding='utf-8') as f:
                        job = json.load(f)
                        all_jobs.append(job)
                except Exception:
                    continue
        
        # Sort by created_at descending (newest first)
        all_jobs.sort(key=lambda x: x.get('created_at', ''), reverse=True)
        
        # Apply pagination
        return all_jobs[offset:offset+limit]
    except Exception:
        return []

def get_stats():
    """Get job statistics for metrics endpoint."""
    try:
        all_jobs = list_jobs(limit=999999, offset=0)
        
        stats = {
            'total': len(all_jobs),
            'queued': 0,
            'running': 0,
            'completed': 0,
            'failed': 0,
            'cancelled': 0,
            'avg_duration': 0
        }
        
        durations = []
        for job in all_jobs:
            status = job.get('status', 'unknown')
            if status == 'queued':
                stats['queued'] += 1
            elif status == 'running':
                stats['running'] += 1
            elif status == 'completed':
                stats['completed'] += 1
            elif status == 'failed':
                stats['failed'] += 1
            elif status == 'cancelled':
                stats['cancelled'] += 1
            
            # Calculate average duration
            created = job.get('created_at')
            updated = job.get('updated_at')
            if created and updated:
                try:
                    from datetime import datetime as dt
                    c_time = dt.fromisoformat(created.replace('Z', '+00:00'))
                    u_time = dt.fromisoformat(updated.replace('Z', '+00:00'))
                    duration_s = (u_time - c_time).total_seconds()
                    if duration_s > 0:
                        durations.append(duration_s)
                except Exception:
                    pass
        
        if durations:
            stats['avg_duration'] = sum(durations) / len(durations)
        
        return stats
    except Exception:
        return {'total': 0, 'queued': 0, 'running': 0, 'completed': 0, 'failed': 0, 'cancelled': 0, 'avg_duration': 0}
