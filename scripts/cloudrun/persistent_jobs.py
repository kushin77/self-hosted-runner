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
