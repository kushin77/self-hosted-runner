# Cloud Finalization Runbook — NexusShield Portal

**Date:** March 10, 2026  
**Status:** Ready for cloud-team execution  
**Backend Deployment:** ✅ Complete and operational (52+ min uptime)

---

## Overview

The NexusShield Portal backend deployment is complete and running on 192.168.168.42. The final step is cloud finalization: executing Terraform applies, KMS checks, and final resource provisioning.

This runbook provides the exact commands for the cloud-team to run.

---

## Prerequisites

Before running the finalize commands:

1. **GCP Service Account Credentials**
   - Path: `/path/to/service-account-key.json`
   - Permissions: GSM admin, KMS admin, Terraform state access
   - Example: `export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json`

2. **Environment Variables**
   - `TF_VAR_environment=production`
   - `TF_VAR_gcp_project=nexusshield-prod`

3. **AWS Credentials** (if KMS in AWS)
   - Set via `~/.aws/credentials` or `AWS_PROFILE=<profile>`

---

## Step 1: Prepare Workspace

```bash
cd /home/akushnir/self-hosted-runner
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
export TF_VAR_environment=production
export TF_VAR_gcp_project=nexusshield-prod
```

---

## Step 2: Run Cloud Finalization Script

```bash
bash scripts/go-live-kit/02-deploy-and-finalize.sh | tee /tmp/go-live-finalize-$(date -u +%Y%m%dT%H%M%SZ).log
```

**What this script does:**
- Validates Terraform state
- Applies Terraform to provision final GCP resources
- Checks KMS key access
- Verifies Secret Manager readiness
- Runs health checks on backend services
- Collects final audit logs

**Expected output:**
```
[✓] Terraform plan validated
[✓] Cloud resources provisioned
[✓] KMS keys accessible
[✓] Secret Manager API ready
[✓] Backend health check passed
[✓] All systems operational
```

---

## Step 3: Run Provisioning Validation

```bash
bash scripts/deployment/provision-operator-credentials.sh --no-deploy --verbose | tee -a /tmp/go-live-finalize-*.log
```

**What this script does:**
- Verifies GSM permissions
- Validates that `OPERATOR_SSH_KEY` secret can be created
- Tests Secret Manager API connectivity
- Confirms all credentials are properly configured

**Expected output:**
```
[✓] GSM admin role verified
[✓] Secret can be created
[✓] Operator credentials ready
[✓] All validations passed
```

---

## Step 4: Collect and Post Logs

Once both scripts complete successfully:

1. **Capture the full log:**
   ```bash
   cat /tmp/go-live-finalize-*.log
   ```

2. **Post to GitHub Issue #2311:**
   - Navigate to: https://github.com/kushin77/self-hosted-runner/issues/2311
   - Paste the complete output as a single comment
   - The automation will:
     - Save the log
     - Compute SHA256 checksum
     - Run verification heuristics
     - Post audit comment
     - Auto-close the issue if successful

---

## Troubleshooting

### Error: "Permission denied" on GCP API calls

**Cause:** Service account lacks required roles.  
**Solution:** Ensure service account has:
- `roles/secretmanager.admin`
- `roles/iam.securityAdmin`
- `roles/compute.admin` (for any compute resources)

```bash
gcloud projects add-iam-policy-binding nexusshield-prod \
  --member=serviceAccount:nexusshield-tfstate-backup@nexusshield-prod.iam.gserviceaccount.com \
  --role=roles/secretmanager.admin
```

### Error: "Terraform state lock timeout"

**Cause:** Another Terraform apply is running or previous run didn't clean up.  
**Solution:** 
```bash
# Check lock status
terraform -chdir=terraform force-unlock <LOCK_ID>

# Or wait 10 minutes and retry
```

### Error: "KMS key not found"

**Cause:** AWS KMS key doesn't exist or isn't accessible.  
**Solution:** Verify AWS credentials and key ARN in Terraform variables.

```bash
aws kms describe-key --key-id <KEY_ARN>
```

---

## Verification

After finalization completes, verify:

1. **Backend is still running:**
   ```bash
   ssh -i ~/.ssh/id_ed25519 akushnir@192.168.168.42 "docker ps | grep nexusshield-backend"
   ```

2. **Secret Manager has credentials:**
   ```bash
   gcloud secrets list --project=nexusshield-prod
   ```

3. **Terraform state is clean:**
   ```bash
   terraform -chdir=terraform show
   ```

---

## Next Steps After Finalization

1. ✅ Post logs to Issue #2311
2. ✅ Wait for automation to verify and close issue
3. ✅ Share link to deployment audit with team
4. ✅ Begin ongoing monitoring setup using [MONITORING_SETUP_GUIDE.md](MONITORING_SETUP_GUIDE.md)
5. ✅ Prepare security hardening (TLS, credential rotation)

---

## Important Notes

- **Do not interrupt** the finalization scripts—they are idempotent and safe to re-run
- **Keep logs**: Retain `/tmp/go-live-finalize-*.log` for audit trail
- **Backend remains operational** during finalization (no downtime)
- **Credentials**: Change `testpass123` database password after finalization

---

## Contact & Support

For issues during cloud finalization:
- Repository: https://github.com/kushin77/self-hosted-runner
- Issue: #2311 for cloud finalization
- Logs: Preserved in `/tmp/go-live-finalize-*.log` and repository audit

---

**Ready to proceed. Cloud-team: execute the commands above and post logs to Issue #2311.**
