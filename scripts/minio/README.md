MinIO artifact helpers

These scripts provide a minimal wrapper around the MinIO `mc` client to upload and
download workflow artifacts to/from an S3-compatible MinIO endpoint. They are intended
for use on self-hosted runners where you control the environment.

Environment variables supported:
- `MINIO_ENDPOINT` - e.g. https://minio.example:9000
- `MINIO_ACCESS_KEY`
- `MINIO_SECRET_KEY`
- `MINIO_BUCKET` - bucket name to use (optional, can be passed per-run)

Examples:

Upload:
```
scripts/minio/upload.sh --file deployment-report.txt --bucket my-bucket --object deployment-report-1234.txt
```

Download:
```
scripts/minio/download.sh --bucket my-bucket --object deployment-report-1234.txt --out deployment-report.txt
```
