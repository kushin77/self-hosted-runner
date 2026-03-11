#!/usr/bin/env python3
"""Simple Redis worker that pops jobs from list 'migration_jobs' and runs the migrator."""
import os
import json
import time
import redis
import sys
sys.path.insert(0, os.path.dirname(__file__))

import persistent_jobs as pj
from run_migrator import run_migrator

REDIS_URL = os.environ.get('REDIS_URL', 'redis://127.0.0.1:6379/0')

def main():
    r = redis.from_url(REDIS_URL)
    print('Connecting to Redis', REDIS_URL)
    while True:
        try:
            item = r.blpop('migration_jobs', timeout=5)
            if not item:
                continue
            _, payload = item
            job = json.loads(payload.decode('utf-8'))
            job_id = job.get('id')
            pj.set_status(job_id, 'running')
            run_migrator(job_id, job)
        except Exception as e:
            print('worker error', e)
            time.sleep(2)

if __name__ == '__main__':
    main()
