#!/usr/bin/env python3
"""Upload rotated audit bundles to immutable cloud storage (GCS or S3).
This script prefers GCS when `GCS_AUDIT_BUCKET` is set, otherwise S3 via `S3_AUDIT_BUCKET`.
"""
import os
import sys
import shutil
from datetime import datetime

def upload_gcs(local_path, bucket, dest_name=None):
    try:
        from google.cloud import storage
        client = storage.Client()
        bucket_obj = client.bucket(bucket)
        dest_name = dest_name or os.path.basename(local_path)
        blob = bucket_obj.blob(dest_name)
        blob.upload_from_filename(local_path)
        print('uploaded to gs://%s/%s' % (bucket, dest_name))
        return True
    except Exception as e:
        print('GCS upload failed:', e)
        return False

def upload_s3(local_path, bucket, dest_name=None):
    try:
        import boto3
        s3 = boto3.client('s3')
        dest_name = dest_name or os.path.basename(local_path)
        s3.upload_file(local_path, bucket, dest_name)
        print('uploaded to s3://%s/%s' % (bucket, dest_name))
        return True
    except Exception as e:
        print('S3 upload failed:', e)
        return False

def main(path):
    bucket_gcs = os.environ.get('GCS_AUDIT_BUCKET')
    bucket_s3 = os.environ.get('S3_AUDIT_BUCKET')
    if not os.path.exists(path):
        print('path missing', path); return 2
    name = 'audit-' + datetime.utcnow().strftime('%Y%m%dT%H%M%SZ') + '-' + os.path.basename(path)
    if bucket_gcs:
        if upload_gcs(path, bucket_gcs, name):
            return 0
    if bucket_s3:
        if upload_s3(path, bucket_s3, name):
            return 0
    print('No configured bucket or upload failed')
    return 3

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('usage: upload_audit.py path/to/audit.jsonl')
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
