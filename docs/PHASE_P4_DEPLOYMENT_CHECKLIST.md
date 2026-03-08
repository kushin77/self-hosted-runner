# Phase P4 Deployment Checklist & Verification Guide

Use this checklist to ensure Phase P4 is deployed correctly and operating as expected.

## Pre-Deployment Checklist

- [ ] Terraform state backend is provisioned and encrypted with KMS
- [ ] Vault instance is accessible and authentication is configured
- [ ] Kubernetes cluster is running (v1.24+) with sufficient resources
- [ ] Docker registry (GHCR/ECR/ACR) is accessible for image pushes
- [ ] DNS is configured for `vault.example.local` and `control-plane.example.local`
- [ ] All 4 implementation PRs (#1565, #1566, #1567, #1569) are merged

## Deployment Phase 1: Infrastructure

### Terraform State Backend (KMS)

```bash
# Deploy
cd infra/backends/aws
terraform apply

# Verify
aws s3api head-bucket --bucket $(terraform output -raw s3_bucket_id)
aws dynamodb describe-table --table-name $(terraform output -raw dynamodb_table_name)

# Checklist
- [ ] S3 bucket created and versioning enabled
- [ ] DynamoDB table created
- [ ] KMS key created with appropriate key policy
- [ ] No public access to S3 bucket
```

### Vault PKI & Kubernetes Auth

```bash
# Deploy PKI
cd infra/vault/pki-provisioning
terraform apply

# Verify PKI
vault list pki/roles
vault read -format=json pki/roles/control-plane-role

# Deploy Kubernetes Auth
cd ../kubernetes-auth
terraform apply

# Verify Kubernetes Auth
vault auth list | grep kubernetes
vault read auth/kubernetes/config

# Checklist
- [ ] PKI root/intermediate CA chain created
- [ ] control-plane-role exists with correct TTL (72h)
- [ ] Kubernetes auth method enabled and configured
- [ ] Service account and token reviewer configured
- [ ] control-plane policy exists and grants PKI access
```

## Deployment Phase 2: Control-Plane (Envoy + Vault Agent)

### Create Namespace & ConfigMaps

```bash
kubectl create namespace control-plane

# Apply base configurations
kubectl apply -n control-plane -f control-plane/envoy/deploy/vault-configmap.yaml
kubectl apply -n control-plane -f control-plane/envoy/deploy/reload-configmap.yaml

# Verify ConfigMaps
kubectl get configmap -n control-plane

# Checklist
- [ ] control-plane namespace created
- [ ] vault-config ConfigMap created with templates
- [ ] reload-script ConfigMap created
```

### Deploy Envoy Deployment

```bash
kubectl apply -n control-plane -f control-plane/envoy/deploy/envoy-deployment.yaml

# Watch rollout
kubectl rollout status deployment/control-plane-envoy -n control-plane

# Verify replicas
kubectl get deployment control-plane-envoy -n control-plane

# Checklist
- [ ] Deployment created with 2 replicas
- [ ] All containers started (envoy, vault-agent, envoy-reloader)
- [ ] Liveness/readiness probes configured
- [ ] Pods running without CrashLoopBackOff
```

### Verify Envoy is Operational

```bash
POD=$(kubectl get pods -n control-plane -l app=control-plane-envoy -o jsonpath='{.items[0].metadata.name}')

# Check admin endpoint
kubectl exec -n control-plane "$POD" -- curl -s http://127.0.0.1:9901/ready

# Check stats
kubectl exec -n control-plane "$POD" -- curl -s http://127.0.0.1:9901/stats | head -10

# Check TLS cert exists
kubectl exec -n control-plane "$POD" -- ls -la /etc/envoy/tls/

# Checklist
- [ ] Admin endpoint responding (HTTP 200)
- [ ] Stats endpoint returning data
- [ ] TLS certificates present and readable
- [ ] Certificate file permissions correct (640 or similar)
```

## Deployment Phase 3: Image Rotation Automation

### Enable Image Rotation Workflow

```bash
# Trigger manual workflow run
gh workflow run image-rotation-trivy.yml --repo kushin77/self-hosted-runner

# Watch execution
gh run list --workflow image-rotation-trivy.yml --repo kushin77/self-hosted-runner -L 3

# View logs
gh run view <run_id> --repo kushin77/self-hosted-runner --log

# Checklist
- [ ] Workflow triggered successfully
- [ ] Docker image built without errors
- [ ] Trivy scan completed and report generated
- [ ] CVE summary logged (HIGH, CRITICAL counts)
- [ ] Workflow logs accessible and readable
```

### Configure Daily Schedule (Optional)

If not already scheduled, update `.github/workflows/image-rotation-trivy.yml`:

```yaml
schedule:
  - cron: '0 2 * * *'  # Daily at 2 AM UTC
```

Then commit and push:

```bash
git add .github/workflows/image-rotation-trivy.yml
git commit -m "chore: enable daily image rotation schedule"
git push
```

## Deployment Phase 4: E2E Validation

### Run E2E Test Script

```bash
# Make executable
chmod +x control-plane/envoy/e2e_test.sh

# Run test
export NAMESPACE=control-plane
export DEPLOYMENT=control-plane-envoy
bash control-plane/envoy/e2e_test.sh

# Expected output
=== E2E Test Passed ===
✓ Envoy mTLS setup working
✓ Certificate rotation detected
✓ No downtime during rotation

# Checklist
- [ ] Pod deployed successfully
- [ ] Envoy admin endpoint ready
- [ ] Certificate extracted and hashed
- [ ] Certificate refresh simulated
- [ ] Reload watcher detected change
- [ ] Pod remained running throughout
```

### Run E2E GitHub Actions Workflow

```bash
# Trigger Kind-based E2E workflow
gh workflow run e2e-envoy-mtls.yml --repo kushin77/self-hosted-runner

# View results
gh run list --workflow e2e-envoy-mtls.yml --repo kushin77/self-hosted-runner -L 1
gh run view <run_id> --repo kushin77/self-hosted-runner

# Checklist
- [ ] Workflow passed (green check)
- [ ] Kind cluster created successfully
- [ ] All manifests applied without errors
- [ ] Deployment reached ready state
- [ ] Smoke test TLS verified
- [ ] Reload triggered and verified
```

## Deployment Phase 5: Runner Pool Provisioning

### Deploy AWS Runners (Example)

```bash
cd infra/examples/aws

terraform init -backend-config="bucket=<TF_BACKEND_S3_BUCKET>" \
  -backend-config="dynamodb_table=terraform-locks" \
  -backend-config="key=phase-p4/aws-runners.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="encrypt=true" \
  -backend-config="kms_key_id=<TF_BACKEND_KMS_KEY_ARN>"

terraform plan -var ami_id=<IMAGE_ID> -out=tfplan
terraform apply tfplan

# Verify runners are launching
aws autoscaling describe-auto-scaling-groups --query 'AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity]'

# Checklist
- [ ] Terraform state initialized with correct backend
- [ ] Plan reviewed and no unexpected changes
- [ ] Apply completed successfully
- [ ] ASG created with desired capacity
- [ ] Instances launching and registering
```

## Post-Deployment Health Checks

### Vault Health

```bash
vault status

# Should show:
# Seal Type: ...
# Sealed: false
# Key Shares: ...

# Verify PKI
vault list pki/
vault list pki_int/

# Verify Auth
vault auth list | grep kubernetes

# Checklist
- [ ] Vault unsealed and running
- [ ] PKI mounts active
- [ ] Kubernetes auth enabled
- [ ] No auth errors or permission denials
```

### Kubernetes Health

```bash
# Check node health
kubectl get nodes

# Check control-plane resources
kubectl top nodes
kubectl top pods -n control-plane

# Check Envoy status
kubectl logs -n control-plane deployment/control-plane-envoy -c envoy --tail=20
kubectl logs -n control-plane deployment/control-plane-envoy -c vault-agent --tail=20

# Check for errors
kubectl get events -n control-plane

# Checklist
- [ ] All nodes Ready
- [ ] Pod CPU/memory reasonable
- [ ] No recent errors or warnings
- [ ] Logs show normal operation
```

### Certificate Rotation

```bash
# Check current certificate age
POD=$(kubectl get pods -n control-plane -l app=control-plane-envoy -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n control-plane "$POD" -c envoy -- openssl x509 -in /etc/envoy/tls/server.crt -noout -dates

# Should show:
# notBefore=... (recent)
# notAfter=... (in ~72 hours)

# Check Vault Agent for template rendering
kubectl logs -n control-plane "$POD" -c vault-agent | grep -i template | tail -5

# Checklist
- [ ] Certificate issued within last 24 hours
- [ ] Expiration is ~72 hours away
- [ ] Vault Agent successfully rendering templates
- [ ] No permission or auth errors
```

## Troubleshooting Quick Reference

| Symptom | Root Cause | Resolution |
|---------|-----------|------------|
| Envoy pod CrashLoopBackOff | Missing TLS cert from Vault Agent | Check vault-agent logs, verify K8s auth |
| Certificate not rotating | Vault Agent stuck or template error | Restart pod, check vault auth logs |
| Terraform state locked | Previous run crashed | `terraform force-unlock <lock_id>` |
| Image rotation workflow fails | Trivy/Docker/registry issue | Check workflow logs, verify registry access |
| E2E test fails | Envoy config issues | Check envoy-deployment.yaml, ConfigMaps |

## Rollback & Recovery

### Rollback Deployment

If Phase P4 deployment causes issues:

```bash
# Scale down
kubectl scale deployment control-plane-envoy --replicas=0 -n control-plane

# Restore previous state from git
git revert <commit-sha>
git push

# Redeploy controlled
kubectl rollout restart deployment/control-plane-envoy -n control-plane
```

### Recover from Terraform State Corruption

```bash
# Backup current state
terraform state pull > state.backup

# Restore from versioned S3
aws s3api get-object --bucket <bucket> --key phase-p4/terraform.tfstate.backup state.restore
terraform state push state.restore

# Verify
terraform plan  # should be clean
```

---

Last updated: March 8, 2026
