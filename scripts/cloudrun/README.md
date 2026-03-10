# Portal Migration Audit & Rotation

This folder contains tools for the portal migration audit trail and automation.

Files:
- `audit_store.py` - append-only JSONL writer with SHA256(prev+payload) chaining.
- `audit_verify.py` - verify chain integrity.
- `upload_audit.py` - upload rotated bundles to GCS or S3.
- `rotate_and_upload_audit.sh` - rotation script (verifies and uploads, archives local gzip).
- `requirements.txt` - Python dependencies for these tools.

Recommended setup (production):

1. Configure an immutable bucket with object versioning:

   - GCS: create bucket with `--versioning` and lock retention/policies.
   - S3: create bucket with versioning and an appropriate lifecycle + MFA delete.

2. Set environment variables for upload:

   - `GCS_AUDIT_BUCKET=your-bucket-name` OR `S3_AUDIT_BUCKET=your-bucket-name`
   - `PORTAL_AUDIT_LOG=/var/log/portal/portal-migrate-audit.jsonl`
   - `AUDIT_ARCHIVE_DIR=/var/log/portal/archive`

3. Install Python deps (prefer inside container):

```bash
python3 -m pip install -r scripts/cloudrun/requirements.txt
```

4. Install systemd units (on the fullstack host):

```bash
sudo cp scripts/systemd/audit-rotate.service /etc/systemd/system/
sudo cp scripts/systemd/audit-rotate.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now audit-rotate.timer
```

Security & Secrets
- Use Vault AppRole for runtime secrets (Vault addr + token via VM secret mount or Vault Agent).
- Prefer Google Secret Manager for GCP deployments behind GSM IAM.
- KMS-wrapped keys should protect any long-term secrets used by the upload tool.

Operations
- Rotation runs daily, verifies chain, uploads, compresses, and archives locally.
- Audit verification can be run manually:

```bash
python3 scripts/cloudrun/audit_verify.py logs/portal-migrate-audit.jsonl
```
