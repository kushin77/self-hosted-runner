# Phase P4 Operator Runbook

This document provides operators with step-by-step instructions for deploying, managing, and troubleshooting the Phase P4 infrastructure (managed-homing control-plane with mTLS, Vault-backed secrets, automated image rotation).

## Prerequisites

- Kubernetes cluster (v1.24+) for control-plane
- Vault instance (v1.13+) with PKI and Kubernetes auth configured
- Terraform >= 1.0
- kubectl, helm, git

## Deployment Steps

### 1. Provision Terraform State Backend (KMS-Encrypted)

```bash
cd infra/backends/aws
terraform init
terraform apply -var project=self-hosted-runner -var environment=phase-p4
terraform output # Save outputs for next steps
```

Store outputs as GitHub Actions secrets:
- `TF_BACKEND_S3_BUCKET`
- `TF_BACKEND_DYNAMODB_TABLE`
- `TF_BACKEND_KMS_KEY_ARN`

### 2. Configure Vault PKI & Kubernetes Auth

```bash
# Configure Vault provider credentials
export VAULT_ADDR=https://vault.example.local
export VAULT_TOKEN=<your-token>

# Provision PKI
cd infra/vault/pki
terraform init -backend-config="bucket=$TF_BACKEND_S3_BUCKET" ...
terraform apply

# Provision Kubernetes auth
cd ../kubernetes-auth
terraform init -backend-config="bucket=$TF_BACKEND_S3_BUCKET" ...
terraform apply \
  -var vault_addr=$VAULT_ADDR \
  -var kubernetes_host=https://kubernetes.default.svc:443 \
  -var kubernetes_ca_cert="$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)" \
  -var kubernetes_token="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
```

### 3. Deploy Envoy Control-Plane

Create namespace and secrets:

```bash
kubectl create namespace control-plane

# Create Envoy ConfigMaps
kubectl apply -n control-plane -f control-plane/envoy/deploy/vault-configmap.yaml
kubectl apply -n control-plane -f control-plane/envoy/deploy/reload-configmap.yaml

# Apply Envoy deployment
kubectl apply -n control-plane -f control-plane/envoy/deploy/envoy-deployment.yaml

# Wait for rollout
kubectl rollout status deployment/control-plane-envoy -n control-plane --timeout=300s
```

### 4. Verify mTLS & Certificate Rotation

Run the E2E test:

```bash
bash control-plane/envoy/e2e_test.sh
```

Expected output:
```
✓ Pod deployed: control-plane-envoy-xxxx
✓ Envoy admin endpoint ready
✓ Certificate hash: abcd1234...
✓ Pod still running after cert refresh
✓ Envoy still responsive after cert refresh
=== E2E Test Passed ===
```

### 5. Set Up Image Rotation Automation

Enable the image rotation workflow:

```bash
# Manually trigger or wait for scheduled run
gh workflow run image-rotation-trivy.yml

# Monitor runs
gh run list --workflow image-rotation-trivy.yml --repo kushin77/self-hosted-runner
```

### 6. Deploy Runner Poolswith Terraform

Configure AWS or Azure runner pools:

**AWS Example:**
```bash
cd infra/examples/aws
terraform init -backend-config="bucket=$TF_BACKEND_S3_BUCKET" ...
terraform apply -var ami_id=ami-xxxxx  # Use output from image-rotation-trivy.yml
```

**Azure Example:**
```bash
cd infra/examples/azure
terraform init -backend-config="bucket=$TF_BACKEND_S3_BUCKET" ...
terraform apply -var resource_group_name=example-rg
```

## Monitoring & Alerting

### Key Metrics

Monitor these Prometheus/CloudWatch metrics:

**Envoy:**
- `envoy_server_uptime` — Envoy uptime
- `envoy_http_ingress_http_requests_total` — Request rate
- `envoy_ssl_connections_ssl_handshake_failure` — TLS errors

**Certificate Rotation:**
- Pod restart frequency (should be ~every 72h due to cert TTL)
- Time from cert change to envoy reload
- Certificate expiration age (should always be < 72h)

**Image Rotation:**
- Trivy scan frequency (daily or on-demand)
- CVE detection rate
- Image push/tag latency

### Health Checks

**Envoy Admin Endpoint:**
```bash
kubectl exec -n control-plane <pod> -- curl http://127.0.0.1:9901/ready
kubectl exec -n control-plane <pod> -- curl http://127.0.0.1:9901/stats | head -20
```

**Vault Status:**
```bash
vault status
vault auth list  # Verify kubernetes auth is enabled
vault list pki/roles  # Verify control-plane-role exists
```

**Runner Registration:**
```bash
# Check for recent registrations in control-plane logs
kubectl logs -n control-plane deployment/control-plane-envoy -c envoy | grep register
```

## Troubleshooting

### Certificate Not Rotating

1. Check Vault Agent logs:
   ```bash
   kubectl logs -n control-plane <pod> -c vault-agent
   ```
   Look for template rendering errors or auth issues.

2. Verify Kubernetes auth role:
   ```bash
   vault read auth/kubernetes/role/control-plane-role
   ```

3. Check token reviewer JWT:
   ```bash
   kubectl get sa -n default  # Verify default SA exists
   ```

### Envoy Not Starting

1. Check deployment status:
   ```bash
   kubectl describe deployment control-plane-envoy -n control-plane
   ```

2. Check TLS volume mount:
   ```bash
   kubectl get configmap control-plane-envoy-vault-config -n control-plane
   ```

3. Verify Cert Permissions:
   ```bash
   kubectl exec -n control-plane <pod> -- ls -la /etc/envoy/tls/
   ```

### Image Rotation Not Triggering

1. Check workflow logs:
   ```bash
   gh run list --workflow image-rotation-trivy.yml --repo kushin77/self-hosted-runner -L 5
   gh run view <run_id> --repo kushin77/self-hosted-runner --log
   ```

2. Verify Trivy can scan:
   ```bash
   trivy image ghcr.io/kushin77/self-hosted-runner:latest
   ```

### Terraform State Corruption / Lock Issues

1. View state lock:
   ```bash
   aws dynamodb get-item --table-name terraform-locks --key '{"LockID":{"S":"phase-p4/terraform.tfstate"}}'
   ```

2. Force unlock (only if truly stuck):
   ```bash
   terraform force-unlock <lock_id>
   ```

3. Recover from state backup:
   ```bash
   aws s3api get-object --bucket <bucket> --key phase-p4/terraform.tfstate.bak tfstate.backup
   terraform state pull > current.tfstate  # Backup current
   terraform state push tfstate.backup
   ```

## Maintenance & Updates

### Certificate TTL Extension

If 72h is too aggressive, update the PKI role:

```bash
vault write pki/roles/control-plane-role ttl=168h max_ttl=720h
```

Then update Terraform:
```bash
# Update infra/vault/pki/main.tf max_ttl and template TTL
```

### Runner Image Updates

Push new images and tag:
```bash
docker tag my-runner:v1.2.3 ghcr.io/kushin77/self-hosted-runner:v1.2.3
docker push ghcr.io/kushin77/self-hosted-runner:v1.2.3
```

Update Terraform variables:
```bash
# Update infra/examples/{aws,azure}/variables.tf image URIs
terraform apply -var image_uri=ghcr.io/kushin77/self-hosted-runner:v1.2.3
```

### Vault PKI Rotation (Root/Intermediate CA)

Plan CA rotation 30 days before expiry:

```bash
# Request new intermediate CA
vault write -format=json pki/intermediate/generate/csr \
  common_name="Phase P4 Intermediate" > csr.json

# Have root CA sign it (external process or in-Vault)
# Store signed cert
vault write pki/intermediate/set-signed certificate=@signed-cert.pem

# Update TTLs and policies as needed
```

## Automation Hooks

The following are automatically triggered:

| Event | Trigger | Action |
|-------|---------|--------|
| Cert near expiry (72h TTL) | Vault Agent | Renew via PKI |
| New cert written | Reload watcher | Signal envoy graceful recycle |
| CVE detected (HIGH+) | Trivy scan | Build new image, push, create PR |
| Main branch push | CI/CD | Run image-rotation GH workflow |
| Terraform apply | GitOps | Infra provisioning with state locking |

---

Last updated: March 8, 2026
