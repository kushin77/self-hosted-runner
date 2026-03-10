# Cloud SQL Auth Proxy Runbook (Phase-2)

Purpose: provide a repeatable, hands-off pattern to connect Cloud Run backend to Cloud SQL when org policy blocks private service networking.

Overview:
- Use Cloud SQL Auth Proxy as a sidecar in Cloud Run (or bundled in the backend image).
- The proxy authenticates using the service account attached to Cloud Run and connects to the database using IAM.
- This avoids creating public IPs or VPC peering if an approved network path exists or if proxy can connect via allowed routes.

Steps (short):
1. Create Cloud SQL instance (if allowed) or request admin to enable service networking.
2. Build `cloud_sql_proxy` sidecar image or use `gcr.io/cloudsql-docker/gce-proxy:1.33.3`.
3. Update `terraform` Cloud Run `template.spec.containers` to include sidecar:
   - container: `cloud_sql_proxy` image
   - args: `-instances=<PROJECT>:<REGION>:<INSTANCE>=tcp:5432 -credential_file=/secrets/cloudsql/sa.json` (or use IAM token mode)
4. Mount secret for service account if using key, or configure Workload Identity to avoid keys.
5. Update backend to connect to `localhost:5432`.
6. Test locally and in staging.

Workarounds & Notes:
- If org policies block both private and public IPs, request org admin to allow the Auth Proxy pattern or provide an approved DB endpoint.
- Prefer Workload Identity (no keys) and use `-enable-iam-auth` flags where supported.

References:
- https://cloud.google.com/sql/docs/postgres/connect-run
- https://github.com/GoogleCloudPlatform/cloud-sql-proxy
