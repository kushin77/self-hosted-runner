#!/usr/bin/env python3
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import persistent_jobs as pj


def main():
    job_id = str(uuid.uuid4())
    job = {'id': job_id, 'foo': 'bar', 'status': 'queued'}
    pj.save_job(job)
    loaded = pj.load_job(job_id)
    if not loaded or loaded.get('id') != job_id:
        print('failed to load saved job')
        sys.exit(2)

    pj.set_status(job_id, 'running')
    loaded2 = pj.load_job(job_id)
    if loaded2.get('status') != 'running':
        print('failed to set status')
        sys.exit(2)

    # cleanup
    path = pj.job_path(job_id)
    if os.path.exists(path):
        os.remove(path)

    print('test_persistent_jobs: OK')


if __name__ == '__main__':
    main()
