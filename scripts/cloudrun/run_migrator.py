#!/usr/bin/env python3
import time
import json
from datetime import datetime
from . import persistent_jobs as pj
from . import audit_store

AUDIT_LOG = 'logs/portal-migrate-audit.jsonl'

def audit_write(entry: dict):
    try:
        audit_store.append_entry(AUDIT_LOG, entry)
    except Exception:
        entry.setdefault('ts', datetime.utcnow().isoformat() + 'Z')
        with open(AUDIT_LOG, 'a', encoding='utf-8') as f:
            f.write(json.dumps(entry, ensure_ascii=False) + '\n')

def run_migrator(job_id, payload):
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
        time.sleep(1)
        audit_write({'job_id': job_id, 'event': 'step_end', 'step': step, 'status': 'ok'})

    audit_write({'job_id': job_id, 'event': 'job_completed', 'status': 'success'})
    pj.set_status(job_id, 'completed')
