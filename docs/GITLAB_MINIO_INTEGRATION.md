# GitLab + MinIO Integration Guide

**Status**: Configuration templates ready for deployment  
**Date**: 2026-03-07  
**Scope**: S3-compatible object storage for GitLab LFS and artifacts

---

## Overview

This guide configures GitLab to use MinIO (S3-compatible) for:
- **LFS (Large File Storage)**: Git Large File Storage backed by MinIO
- **Artifacts**: CI/CD pipeline artifacts stored in MinIO buckets
- **Packages**: Package registry artifacts (optional)

### Benefits
✅ Self-hosted object storage (no external S3 dependency)  
✅ Budget-friendly with MinIO on-premises  
✅ Full control over data locality and retention  
✅ Automated failover via cascading backup tiers  

---

## Configuration

### MinIO Buckets

Create three buckets in MinIO (via `mc` CLI or web console):

```bash
# Using MinIO client
mc alias set myminio http://mc.elevatediq.ai:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

# Create buckets
mc mb myminio/gitlab-lfs
mc mb myminio/gitlab-artifacts
mc mb myminio/gitlab-packages
```

### GitLab Helm Values

If deploying GitLab via Helm, use the following values fragment in `values-gitlab.yaml`:

```yaml
global:
  # ... other GitLab config ...
  object_storage:
    enabled: true
    proxy_download: true

gitlab:
  lfs:
    enabled: true
    objectStore:
      connection:
        secret: gitlab-minio-secret
        key: connection
  artifacts:
    objectStore:
      connection:
        secret: gitlab-minio-secret
        key: connection
  uploads:
    objectStore:
      connection:
        secret: gitlab-minio-secret
        key: connection
  packages:
    objectStore:
      connection:
        secret: gitlab-minio-secret
        key: connection

# MinIO connection secret
secrets:
  minio:
    connection: |
      provider: AWS
      region: us-east-1
      aws_access_key_id: ${MINIO_ACCESS_KEY}
      aws_secret_access_key: ${MINIO_SECRET_KEY}
      aws_signature_version: 4
      endpoint: http://mc.elevatediq.ai:9000
      path_style: true
      use_path_style_endpoint: true
```

### GitLab omnibus-gitlab.rb

If using omnibus (Docker/package), add to `gitlab.rb`:

```ruby
# External object storage (MinIO S3-compatible)

###! MinIO S3-compatible configuration
gitlab_rails['object_store_enabled'] = true
gitlab_rails['object_store_remote_directory'] = 'gitlab'
gitlab_rails['object_store_connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => ENV['MINIO_ACCESS_KEY'],
  'aws_secret_access_key' => ENV['MINIO_SECRET_KEY'],
  'endpoint' => 'http://mc.elevatediq.ai:9000',
  'path_style' => true,
  'use_path_style_endpoint' => true
}

# LFS objects
gitlab_rails['lfs_object_store_enabled'] = true
gitlab_rails['lfs_object_store_remote_directory'] = 'gitlab-lfs'
gitlab_rails['lfs_object_store_connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => ENV['MINIO_ACCESS_KEY'],
  'aws_secret_access_key' => ENV['MINIO_SECRET_KEY'],
  'endpoint' => 'http://mc.elevatediq.ai:9000',
  'path_style' => true,
  'use_path_style_endpoint' => true
}

# Artifacts
gitlab_rails['artifacts_object_store_enabled'] = true
gitlab_rails['artifacts_object_store_remote_directory'] = 'gitlab-artifacts'
gitlab_rails['artifacts_object_store_connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => ENV['MINIO_ACCESS_KEY'],
  'aws_secret_access_key' => ENV['MINIO_SECRET_KEY'],
  'endpoint' => 'http://mc.elevatediq.ai:9000',
  'path_style' => true,
  'use_path_style_endpoint' => true
}

# Uploads (avatars, project exports, etc.)
gitlab_rails['uploads_object_store_enabled'] = true
gitlab_rails['uploads_object_store_remote_directory'] = 'gitlab-uploads'
gitlab_rails['uploads_object_store_connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => ENV['MINIO_ACCESS_KEY'],
  'aws_secret_access_key' => ENV['MINIO_SECRET_KEY'],
  'endpoint' => 'http://mc.elevatediq.ai:9000',
  'path_style' => true,
  'use_path_style_endpoint' => true
}

# Packages (npm, Maven, etc.)
gitlab_rails['packages_object_store_enabled'] = true
gitlab_rails['packages_object_store_remote_directory'] = 'gitlab-packages'
gitlab_rails['packages_object_store_connection'] = {
  'provider' => 'AWS',
  'region' => 'us-east-1',
  'aws_access_key_id' => ENV['MINIO_ACCESS_KEY'],
  'aws_secret_access_key' => ENV['MINIO_SECRET_KEY'],
  'endpoint' => 'http://mc.elevatediq.ai:9000',
  'path_style' => true,
  'use_path_style_endpoint' => true
}
```

---

## Validation

### Test LFS Upload

```bash
# Create a test repository
git init test-repo && cd test-repo

# Configure LFS
git lfs install
echo "test file" > large.bin
git lfs track "*.bin"
git add .gitattributes large.bin
git commit -m "Add LFS test file"
git remote add origin https://gitlab.internal.elevatediq.com/test/repo.git
git push -u origin main

# Verify upload went to MinIO
mc ls myminio/gitlab-lfs/
```

### Test Artifact Upload

Use the included demo pipeline (`.gitlab-ci.yml` in this directory).

### Health Check

From GitLab admin panel:
1. Navigate to **Admin > System > Applications > Object Storage**
2. Verify all buckets are accessible
3. Check object counts in MinIO dashboard

---

## Monitoring & Metrics

MinIO Prometheus metrics are exposed at `http://mc.elevatediq.ai:9000/minio/v2/metrics/cluster`.

Add to Prometheus scrape config:
```yaml
- job_name: 'minio'
  metrics_path: '/minio/v2/metrics/cluster'
  static_configs:
    - targets: ['mc.elevatediq.ai:9000']
```

Key metrics to alert on:
- `minio_disk_used_bytes` > threshold
- `minio_bucket_usage_total_bytes` > threshold
- `minio_online` == 0 (down)

---

## Troubleshooting

### "Connection refused" from GitLab

**Symptom**: GitLab logs show `Connection refused` to MinIO endpoint.

**Diagnosis**:
```bash
# From GitLab container
curl -v http://mc.elevatediq.ai:9000/minio/health/live
```

**Fix**:
1. Verify MinIO is running: `mc admin info myminio`
2. Check firewall/network policy allows 9000 from GitLab pod/container
3. Verify DNS resolves: `nslookup mc.elevatediq.ai`

### S3 signature mismatch

**Symptom**: `SignatureDoesNotMatch` errors in GitLab logs.

**Diagnosis**:
```bash
# Re-check credentials
echo "$MINIO_ACCESS_KEY"
echo "$MINIO_SECRET_KEY"
```

**Fix**:
1. Regenerate MinIO service account credentials
2. Update `gitlab.rb` or Helm values with new credentials
3. Restart GitLab (`gitlab-ctl reconfigure` or Helm upgrade)

### Bucket permission errors

**Symptom**: `Access Denied` errors when uploading.

**Fix**:
```bash
# Check bucket policies
mc policy info myminio/gitlab-lfs

# Grant read/write to MinIO user
mc admin user info myminio gitlab-user
mc admin policy attach myminio readwrite username=gitlab-user
```

---

## Backup & Disaster Recovery

### Backup Strategy

MinIO buckets should be backed up daily:
```bash
# Mirror to AWS S3 (example)
mc mirror --watch myminio/gitlab-lfs aws-s3/gitlab-lfs-backup
```

### Restore from Backup

```bash
# Restore from backup
mc mirror aws-s3/gitlab-lfs-backup myminio/gitlab-lfs
```

---

## References

- [GitLab Object Storage Management](https://docs.gitlab.com/ee/administration/object_storage.html)
- [MinIO S3 Compatibility](https://min.io/docs/minio/linux/operations/concepts/s3-compatibility.html)
- [GitLab + MinIO Blog Post](https://blog.min.io/gitlab-minio-integration/)

---

## Deployment Checklist

- [ ] MinIO buckets created (gitlab-lfs, gitlab-artifacts, gitlab-packages, gitlab-uploads)
- [ ] Service account credentials configured
- [ ] GitLab config updated (`gitlab.rb` or Helm values)
- [ ] GitLab restarted/upgraded
- [ ] Admin panel confirms object storage accessible
- [ ] Demo pipeline run successfully (LFS + artifact upload)
- [ ] Prometheus metrics configured
- [ ] Backup automation enabled

---

**Status**: Ready for production deployment  
**Maintenance**: Quarterly review of usage and quotas  
**Escalation**: If object storage unavailable, GitLab pipeline uploads fail; notify ops immediately.
