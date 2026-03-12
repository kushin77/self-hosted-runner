# Quick Deployment Guide - Host Crash Analysis System

**Time to Deploy:** ~10 minutes  
**Downtime:** None  
**Rollback:** Simple (Terraform destroy)

## Prerequisites Check

```bash
# Verify you have:
which gcloud
which terraform
which kubectl
gcloud auth application-default print-access-token > /dev/null && echo "✓ Auth OK"
```

## Step 1: Prepare GCP Resources (1 min)

```bash
export PROJECT_ID="my-gcp-project"  # Change this
export REGION="us-central1"
export AUDIT_BUCKET="gs://host-crash-analysis-audit-$(date +%s)"

# Create GCS bucket with Object Lock
gsutil mb -p "$PROJECT_ID" -l "$REGION" "$AUDIT_BUCKET"
gsutil retention set 365d "$AUDIT_BUCKET"

# Create Workload Identity service account
SA_NAME="host-crash-analysis"
gcloud iam service-accounts create "$SA_NAME" \
  --project="$PROJECT_ID" \
  --display-name="Host Crash Analysis Automation"

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant GCS permissions
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/storage.objectCreator" \
  --condition=None

echo "Service Account: $SA_EMAIL"
echo "Audit Bucket: $AUDIT_BUCKET"
```

## Step 2: Configure Terraform (2 min)

```bash
cd terraform/host-monitoring

# Copy and configure
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
cat > terraform.tfvars <<EOF
gcp_project_id          = "$PROJECT_ID"
gcp_region              = "$REGION"
gke_cluster_name        = "primary-gke-cluster"     # Change to your cluster
gke_zone                = "us-central1-a"            # Change to your zone
gke_workload_identity_sa = "$SA_EMAIL"
gcs_audit_bucket        = "$AUDIT_BUCKET"
slack_webhook_url       = ""  # Optional: add your webhook URL
EOF

cat terraform.tfvars
```

## Step 3: Deploy (3 min)

```bash
# Initialize Terraform
terraform init

# Plan
terraform plan -out=tfplan

# Apply (idempotent, safe to re-run)
terraform apply tfplan

# Show outputs
terraform output
```

## Step 4: Verify Deployment (2 min)

```bash
# Check namespace
kubectl get ns monitoring
kubectl get all -n monitoring

# Check CronJob
kubectl get cronjob -n monitoring
kubectl describe cronjob host-crash-analyzer -n monitoring

# Check RBAC
kubectl get serviceaccount host-crash-analysis -n monitoring
kubectl get clusterrole host-crash-analysis
```

## Step 5: Test (2 min - optional)

```bash
# Create a one-time test job
kubectl create job host-crash-analysis-manual-1 \
  --from=cronjob/host-crash-analyzer \
  -n monitoring

# Monitor execution
kubectl get job -n monitoring
watch kubectl get pod -n monitoring -l job-name=host-crash-analysis-manual-1

# View logs
kubectl logs -n monitoring \
  $(kubectl get pod -n monitoring -l job-name=host-crash-analysis-manual-1 -o jsonpath='{.items[0].metadata.name}')

# Verify audit logs in GCS
gsutil ls "$AUDIT_BUCKET/"
```

## Verification Checklist

- [ ] GCS bucket created with Object Lock
- [ ] Workload Identity service account created
- [ ] Terraform plan reviewed carefully
- [ ] Terraform apply succeeded
- [ ] K8s namespace exists
- [ ] K8s CronJob exists and scheduled
- [ ] ServiceAccount + ClusterRole bound
- [ ] Test job ran successfully
- [ ] Audit logs visible in GCS

## What Happens Next?

**Daily at 2 AM UTC:**
1. Kubernetes launches the CronJob Pod
2. `host-crash-analyzer.py` runs analysis (~15 seconds)
3. If alerts detected:
   - `host-remediation.sh` executes (~90 seconds)
   - Old snaps cleaned
   - Temp files removed
   - Logs rotated & compressed
   - Journal pruned
   - Docker system pruned
4. JSONL audit trail pushed to GCS (immutable)
5. Slack notification sent (if configured)

## Rollback (if needed)

```bash
cd terraform/host-monitoring

# Destroy all resources
terraform destroy

# Verify cleanup
kubectl get ns monitoring  # Should be gone
gsutil ls gs://host-crash-analysis-audit-*  # Still available for audit
```

## Monitoring

**Check Audit Logs:**
```bash
# List all audit logs
gsutil ls -r "$AUDIT_BUCKET/"

# View latest report
gsutil cat "$AUDIT_BUCKET"/$(hostname)/latest.jsonl | jq .

# Download for analysis
gsutil -m cp "$AUDIT_BUCKET"/*.jsonl .
```

**Monitor CronJob:**
```bash
# Watch recent jobs
kubectl get job -n monitoring --watch

# Check next scheduled run
kubectl describe cronjob host-crash-analyzer -n monitoring | grep "Schedule:"

# View logs from last 3 runs
kubectl logs -n monitoring -l app=host-crash-analysis --tail=100 -f
```

## Troubleshooting

**CronJob not running?**
```bash
kubectl describe cronjob host-crash-analyzer -n monitoring
kubectl get events -n monitoring --sort-by='.lastTimestamp'
```

**Secrets not accessible?**
```bash
# Test Workload Identity
kubectl run -it test-wi \
  --image=google/cloud-sdk:slim \
  --serviceaccount=host-crash-analysis \
  -n monitoring \
  -- gcloud secrets list --project="$PROJECT_ID"
```

**Audit logs not in GCS?**
```bash
# Check permissions
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:$SA_EMAIL"

# Test manually
gsutil cp /etc/hostname "$AUDIT_BUCKET/test.txt"
```

---

## Success Indicators

✅ CronJob visible in `kubectl get cronjob`  
✅ ServiceAccount with proper RBAC  
✅ After 2 AM UTC tomorrow, job runs automatically  
✅ JSONL audit logs appear in GCS  
✅ Slack notification received (if configured)  
✅ Zero manual intervention needed  

---

**Time to Full Setup:** ~10 minutes  
**Complexity:** Low (Terraform handles everything)  
**Downtime:** None  
**Risk:** Minimal (no existing systems modified)  

For detailed operations, see `terraform/host-monitoring/README.md`
