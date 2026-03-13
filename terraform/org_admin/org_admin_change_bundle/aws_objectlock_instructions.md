AWS S3 Object Lock Instructions (for AWS Admins)
===============================================

Purpose
-------
Enable or verify Object Lock (WORM) behavior for the compliance audit bucket.

Notes
-----
- S3 Object Lock can only be enabled when creating a bucket. If existing bucket requires Object Lock, you must create a new bucket with Object Lock enabled and migrate objects.
- Work with AWS org admins to ensure the bucket is created with `ObjectLockEnabledForBucket=true` and proper retention configured.

Commands (AWS CLI)
-------------------
```bash
# Check if object lock is enabled for existing bucket
aws s3api get-object-lock-configuration --bucket nexusshield-compliance-logs || true

# If creating a new bucket with Object Lock
aws s3api create-bucket --bucket nexusshield-compliance-logs-locked --region us-east-1 --object-lock-enabled-for-bucket

# Put object retention on an object
aws s3api put-object-retention --bucket nexusshield-compliance-logs --key audit-trail.jsonl --retention "{\"Mode\": \"GOVERNANCE\", \"RetainUntilDate\": \"2033-03-13T00:00:00Z\"}"

# Verify
aws s3api get-object-retention --bucket nexusshield-compliance-logs --key audit-trail.jsonl
```

Audit
-----
- Provide the S3 console link and CloudTrail logs showing ObjectLock configuration change.
