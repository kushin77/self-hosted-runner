Release: NexusShield Production Finalization - 2026-03-10
===============================================

Summary
-------
- Completed hands-off production finalization for NexusShield on 2026-03-10.
- Key outcomes: backend & image-pin services deployed, runtime fixes applied,
  Terraform state imported and pinned image digest committed, scheduler created,
  audit committed, and RCA issue closed.

Details
-------
- Pinned `image-pin-service` image to digest: sha256:BASE64_BLOB_REDACTED
- `backend/Dockerfile` & `backend/Dockerfile.prod`: added `npm ci` fallback to `npm install` when `package-lock.json` is absent.
- `tools/image_pin_service/Dockerfile`: added gunicorn -> python fallback to ensure startup compatibility.
- Terraform: imported existing Cloud Run service into `terraform/image_pin` state, applied update to pin image, created `image-pin-scheduler` job.
- Committed `terraform/image_pin/terraform.tfvars`, `terraform.tfstate` and plan for immutability/audit.
- Closed GitHub issue #2351 (RCA: image-pin-service startup failure).
- Performed authenticated smoke test against `/pin` (200 OK) — functionality verified.

Credentials & Security
----------------------
- No long-lived SA keys remain on disk; ephemeral credentials were removed.
- Secrets and automation use Google Secret Manager and project service accounts per constraints.

Next recommended steps
----------------------
1. Optional: Create a formal GitHub release tag from this branch.
2. Optional: Run a scheduled-trigger integration test of `image-pin-scheduler`.
3. Monitor Cloud Run metrics and Cloud Scheduler logs for 24 hours.

Audit: commit `terraform/image_pin` contents and `artifacts-archive/audit` files contain the full action history.

Contact: ops@nexusshield.example (placeholder)
