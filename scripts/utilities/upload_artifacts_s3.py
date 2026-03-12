#!/usr/bin/env python3
import os
import sys
import boto3
from botocore.exceptions import ClientError

bucket = os.environ.get('ARCHIVE_S3_BUCKET','akushnir-milestones-20260312')
profile = os.environ.get('AWS_PROFILE','dev')
prefix = os.environ.get('ARCHIVE_PREFIX','milestones-assignments')
root = os.path.join(os.path.dirname(__file__), '..', '..', 'artifacts', 'milestones-assignments')
root = os.path.abspath(root)

session = boto3.Session(profile_name=profile)
s3 = session.resource('s3')
client = session.client('s3')

if not os.path.isdir(root):
    print('Artifact directory missing:', root)
    sys.exit(1)

uploaded = []
for fname in sorted(os.listdir(root)):
    path = os.path.join(root, fname)
    if not os.path.isfile(path):
        continue
    key = f"{prefix}/{fname}"
    try:
        print('Uploading', path, '->', f's3://{bucket}/{key}')
        client.upload_file(path, bucket, key)
        uploaded.append(key)
    except ClientError as e:
        print('Upload failed for', path, e)

print('\nUploaded objects:')
for k in uploaded:
    print(k)

print('\nListing prefix in bucket:')
try:
    resp = client.list_objects_v2(Bucket=bucket, Prefix=prefix)
    for obj in resp.get('Contents', []):
        print(obj['Key'], obj['Size'])
except ClientError as e:
    print('List failed', e)

