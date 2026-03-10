# Credential Rotation Runbook

Purpose
-------
Document the automated and manual procedures to rotate production credentials for NexusShield Portal (project: nexusshield-prod). This runbook follows the governance requirements: immutable, ephemeral, idempotent, no-ops, hands-off, and uses GSM / Vault / KMS as primary credential stores.

Scope
-----
- Google Secret Manager (GSM)
- HashiCorp Vault (if used) or equivalent
- Google Cloud KMS (symmetric/asymmetric keys)
- Service account keys and short-lived tokens

Principles
----------
- Prefer automatic rotation where supported (GSM native rotation).
- Use short-lived credentials and exchange patterns (OAuth, workload identity) instead of long-lived service account keys whenever possible.
- All rotations must be recorded in audit logs and documented in Git (immutable record).
- Rollouts must be idempotent: automated runs can be re-run safely.

Rotation Schedule (recommended)
--------------------------------
- GSM secrets: rotate every 30 days (or as policy requires)
- Vault-managed secrets: rotate per organizational schedule (e.g., 30–90 days)
- KMS keys: schedule automatic key rotation via KMS policy (annually or per policy)
- Service account keys: rotate every 7 days for critical accounts; prefer short-lived tokens via Workload Identity

Automations (examples)
----------------------

1) GSM secret rotation (example)

Use Secret Manager automatic rotation when supported. Example Terraform snippet (reference only):

```hcl
resource "google_secret_manager_secret" "portal_secret_example" {
  secret_id = "portal-secret-example"
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "initial" {
  secret      = google_secret_manager_secret.portal_secret_example.id
  secret_data = var.portal_secret_example
}

resource "google_secret_manager_secret_rotation" "rotation" {
  secret = google_secret_manager_secret.portal_secret_example.id
  rotation_period = "2592000s" # 30 days
}
```

2) Vault rotation (example)

- Use Vault's dynamic secrets where possible (lease-based). Configure a rotation job that renews or re-issues credentials and updates GSM.

3) KMS key rotation

- Enable KMS key rotation schedule (e.g., `gcloud kms keys update --rotation-period`), and update any dependent services to reference new key versions.

Service Account Key Migration (recommended)
-----------------------------------------
- Replace static service account keys with Workload Identity or short-lived OAuth tokens.
- If keys exist, rotate them programmatically and remove old keys:

```sh
# list keys
gcloud iam service-accounts keys list --iam-account=terraform-deployer@nexusshield-prod.iam.gserviceaccount.com
# create new key (store securely and rotate)
gcloud iam service-accounts keys create /tmp/new-tf-key.json --iam-account=terraform-deployer@nexusshield-prod.iam.gserviceaccount.com
# remove old key (use KEY_ID from previous list)
gcloud iam service-accounts keys delete KEY_ID --iam-account=terraform-deployer@nexusshield-prod.iam.gserviceaccount.com
```

Runbook: Procedural Steps (high level)
-------------------------------------
1. Create new secret/key in target store (GSM/Vault/KMS).
2. Deploy updated secret to consumers in a canary subset (1 instance / revision) and validate health checks.
3. Promote updated secret globally after successful canary verification.
4. Revoke previous secret/key versions only after successful verification and retention window expiry.
5. Record the rotation event in Git: add entry to `/docs/credential-rotation.md` and tag the commit with rotation metadata.

Rollback
--------
- If consumer fails with new secret, immediately revert configuration to previous secret version and investigate logs. Do not delete previous secrets until rollback window elapses.

Owners & Contacts
-----------------
- Security Lead: @security-oncall (update per org)
- Platform: @platform-oncall
- Operations runbook: `docs/credential-rotation.md`

Acceptance Criteria
-------------------
- A documented runbook exists at this path.
- Automation tasks (scripts/terraform snippets) are referenced and owned.
- Issue tracking created for scheduling and verification.

Notes
-----
- This runbook is intentionally prescriptive but implementation-light. Use the linked issues to track automation work.
