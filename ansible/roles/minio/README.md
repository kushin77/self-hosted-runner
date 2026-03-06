# MinIO Artifact Storage Role

Deploys MinIO S3-compatible artifact storage for GitHub Actions artifact uploads.

## Features

- Idempotent container deployment
- Health checks and auto-restart
- Bucket initialization
- Network integration with Caddy proxy

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `minio_root_user` | minioadmin | Root user |
| `minio_root_password` | (required) | Root password |
| `minio_bucket` | github-actions-artifacts | S3 bucket name |
| `minio_port` | 9000 | S3 API port |
| `minio_console_port` | 9001 | Console UI port |
| `minio_data_path` | /data/minio | Data persistence path |

## Usage

```yaml
- hosts: minio_servers
  roles:
    - role: minio
      vars:
        minio_root_password: "your-secure-password"
        minio_bucket: "github-actions-artifacts"
```

## Compliance

- Immutable: All config via role variables
- Sovereign: Self-hosted, no external dependencies
- Ephemeral: Artifacts are temporary
- Independent: No dependency on other services
