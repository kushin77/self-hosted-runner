# EKS Cluster Bootstrap and Secret Automation Runbook

## Overview

This runbook documents the complete setup, deployment, and verification process for the EKS cluster with multi-cloud secret management (Vault, GSM, AWS Secrets Manager).

## Prerequisites

- AWS CLI v2 configured with appropriate credentials
- Terraform v1.5+
- kubectl v1.29+
- helm v3.12+
- Docker (for building container images)
- Vault instance accessible from EKS cluster
- GCP credentials for GSM access (if using GSM provider)

## Phase 1: Terraform Planning and Review

### 1.1 Initialize Terraform

```bash
cd /home/akushnir/self-hosted-runner/terraform
terraform init
```

### 1.2 Plan EKS Cluster Deployment

```bash
terraform plan -out=eks-cluster.plan \
  -var="cluster_name=milestone-organizer-eks" \
  -var="region=us-east-1" \
  -var="vpc_id=vpc-xxxxx" \
  -var="subnet_ids=[\"subnet-xxxxx\",\"subnet-yyyyy\"]" \
  -var="private_subnet_ids=[\"subnet-private-1\",\"subnet-private-2\",\"subnet-private-3\"]" \
  -var="desired_size=3" \
  -var="max_size=10" \
  -var="vault_address=https://vault.example.com" \
  -var="vault_namespace=admin"
```

### 1.3 Review Plan Output

- Verify cluster name, version, and node group sizing
- Confirm security group ranges (10.0.0.0/8 for internal traffic)
- Ensure subnet allocation includes private subnets for nodes
- Check OIDC provider creation for IRSA

## Phase 2: Deploy EKS Cluster

### 2.1 Apply Terraform Configuration

```bash
terraform apply eks-cluster.plan
```

**Expected output:**
- EKS cluster created
- Node group with 3 nodes (desired size)
- OIDC provider for IRSA configured
- Kubernetes namespaces created: `kube-system`, `workloads`, `cron-jobs`

### 2.2 Verify Cluster Creation

```bash
# Check cluster status
aws eks describe-cluster \
  --name milestone-organizer-eks \
  --region us-east-1 \
  --query 'cluster.status'

# Should output: ACTIVE
```

### 2.3 Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name milestone-organizer-eks

# Verify connection
kubectl cluster-info
kubectl get nodes
```

**Expected output:** 3 nodes in Ready state

## Phase 3: Verify CSI Driver Installation

### 3.1 Check Secrets Store CSI Driver

```bash
# List Helm releases
helm list -n kube-system | grep secrets-store

# Verify CSI driver pod
kubectl get pods -n kube-system | grep secrets-store-csi-driver

# Check CSI driver class
kubectl get csidriver
```

**Expected output:**
- secrets-store-csi-driver pod running
- CSI driver class `secrets-store.csi.k8s.io` registered

### 3.2 Verify Vault Provider Installation

```bash
# Check Vault provider Helm release
helm list -n kube-system | grep vault

# Verify Vault provider pod (if installed)
kubectl get pods -n kube-system | grep vault-provider
```

## Phase 4: Deploy SecretProviderClass Manifests

### 4.1 Create Vault SecretProviderClass

```bash
# Set environment variables
export VAULT_ADDRESS="https://vault.example.com"
export VAULT_NAMESPACE="admin"

# Template and apply Vault provider
envsubst < terraform/modules/eks/templates/secret_provider_vault.yaml | \
  kubectl apply -f -

# Verify creation
kubectl get secretproviderclass -n cron-jobs
```

### 4.2 Create GSM SecretProviderClass

```bash
# Set environment variables
export GCP_PROJECT_ID="your-gcp-project"

# Template and apply GSM provider
envsubst < terraform/modules/eks/templates/secret_provider_gsm.yaml | \
  kubectl apply -f -

# Verify creation
kubectl get secretproviderclass -n cron-jobs
kubectl describe secretproviderclass gsm-database-secrets -n cron-jobs
```

## Phase 5: Deploy and Configure CronJob

### 5.1 Prepare CronJob Manifest

```bash
# Set environment variables
export CONTAINER_IMAGE="milestone-organizer:latest"
export AWS_REGION="us-east-1"
export IRSA_ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/milestone-organizer-eks-cronjob-role"

# Template the CronJob manifest
envsubst < terraform/modules/eks/templates/cronjob_manifest.yaml > /tmp/milestone-cronjob.yaml

# Review the manifest before applying
cat /tmp/milestone-cronjob.yaml
```

### 5.2 Deploy CronJob

```bash
# Apply CronJob manifest
kubectl apply -f /tmp/milestone-cronjob.yaml

# Verify deployment
kubectl get cronjob -n cron-jobs
kubectl describe cronjob milestone-organizer -n cron-jobs

# Check service account
kubectl get sa -n cron-jobs
kubectl describe sa milestone-organizer -n cron-jobs
```

**Expected output:**
- CronJob created with schedule "0 */6 * * *"
- Service account `milestone-organizer` with IRSA annotation

## Phase 6: Verify IRSA Configuration

### 6.1 Test IRSA Role Assumption

```bash
# Run a test pod with the CronJob service account
kubectl run -it --rm debug \
  --image=amazon/aws-cli:latest \
  --serviceaccount=milestone-organizer \
  -n cron-jobs \
  -- sts get-caller-identity

# Expected output: Shows IRSA role ARN
```

### 6.2 Test S3 Access

```bash
# Run pod with S3 access test
kubectl run -it --rm s3-test \
  --image=amazon/aws-cli:latest \
  --serviceaccount=milestone-organizer \
  -n cron-jobs \
  -- s3 ls s3://your-bucket/
```

## Phase 7: Test Secret Access

### 7.1 Test Vault Secret Mount

```bash
# Create a test pod with Vault secret access
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: vault-secret-test
  namespace: cron-jobs
spec:
  serviceAccountName: milestone-organizer
  containers:
  - name: test
    image: alpine:latest
    volumeMounts:
    - name: secrets-vault
      mountPath: /mnt/secrets-vault
    command:
    - sh
    - -c
    - |
      while true; do
        echo "Vault secrets:"
        ls -la /mnt/secrets-vault/
        sleep 10
      done
  volumes:
  - name: secrets-vault
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: vault-database-secrets
EOF

# Check mounted secrets
kubectl logs vault-secret-test -n cron-jobs
```

### 7.2 Test GSM Secret Mount

```bash
# Create a test pod with GSM secret access
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gsm-secret-test
  namespace: cron-jobs
spec:
  serviceAccountName: milestone-organizer
  containers:
  - name: test
    image: google/cloud-sdk:latest
    volumeMounts:
    - name: secrets-gsm
      mountPath: /mnt/secrets-gsm
    command:
    - sh
    - -c
    - |
      echo "GSM secrets:"
      ls -la /mnt/secrets-gsm/
      echo "GSM secret contents:"
      cat /mnt/secrets-gsm/db-password 2>/dev/null || echo "Secret not readable"
  volumes:
  - name: secrets-gsm
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: gsm-database-secrets
EOF

# Check mounted secrets
kubectl logs gsm-secret-test -n cron-jobs
```

## Phase 8: Deploy and Test on Worker Node

### 8.1 SSH to Worker Node 192.168.168.42

```bash
# Get worker node name and IP
kubectl get nodes -o wide

# SSH to the specific node
ssh -i /path/to/key ec2-user@192.168.168.42

# Verify cluster connectivity from node
kubectl get nodes --kubeconfig=/etc/kubernetes/kubelet.conf
```

### 8.2 Run Deploy Script

```bash
# Transfer the deployment script
scp -i /path/to/key \
  /home/akushnir/self-hosted-runner/deploy/milestone-organizer-deploy-and-test.sh \
  ec2-user@192.168.168.42:/tmp/

# Execute deployment script
ssh -i /path/to/key ec2-user@192.168.168.42 \
  "bash /tmp/milestone-organizer-deploy-and-test.sh"
```

**Expected output:**
- Container image pulled successfully
- CronJob verified on cluster
- Initial test execution completed
- Logs streamed to CloudWatch

### 8.3 Verify Container Execution

```bash
# Monitor job execution
kubectl get jobs -n cron-jobs -w

# Check pod logs
kubectl logs -f -n cron-jobs job/milestone-organizer-<timestamp>

# Verify S3 archival
aws s3 ls s3://your-bucket/milestone-organizer/ --recursive
```

## Phase 9: Monitor and Verify CronJob

### 9.1 Monitor CronJob Execution

```bash
# Watch CronJob schedule
kubectl get cronjobs -n cron-jobs -w

# View CronJob history
kubectl get jobs -n cron-jobs --sort-by=.metadata.creationTimestamp

# Check recent job status
kubectl get jobs -n cron-jobs -o jsonpath='{.items[-3:].metadata.name}'
```

### 9.2 CloudWatch Logs Integration

```bash
# Retrieve logs from CloudWatch
aws logs tail /aws/eks/milestone-organizer-eks --follow

# Filter for CronJob logs
aws logs filter-log-events \
  --log-group-name /aws/eks/milestone-organizer-eks \
  --filter-pattern "milestone-organizer"
```

### 9.3 Verify S3 Archival

```bash
# List archived data
aws s3 ls s3://your-bucket/milestone-organizer/ --recursive

# Check latest archive timestamp
aws s3 ls s3://your-bucket/milestone-organizer/ \
  --recursive \
  --human-readable \
  --summarize
```

## Troubleshooting

### Issue: CronJob pods not starting

```bash
# Check CronJob status
kubectl describe cronjob milestone-organizer -n cron-jobs

# Check pod events
kubectl describe pods -n cron-jobs -l app=milestone-organizer

# Check node resources
kubectl describe nodes
kubectl top nodes
```

### Issue: Secret not accessible in pod

```bash
# Verify SecretProviderClass
kubectl get secretproviderclass -n cron-jobs
kubectl describe secretproviderclass vault-database-secrets -n cron-jobs

# Check CSI driver logs
kubectl logs -n kube-system -l app=secrets-store-csi-driver

# Verify IRSA role assumption
kubectl run -it --rm debug \
  --image=amazon/aws-cli:latest \
  --serviceaccount=milestone-organizer \
  -n cron-jobs \
  -- sts get-caller-identity
```

### Issue: S3 upload failing

```bash
# Verify IRSA role permissions
aws iam get-role-policy \
  --role-name milestone-organizer-eks-cronjob-role \
  --policy-name milestone-organizer-eks-cronjob-s3-access

# Test S3 access from pod
kubectl run -it --rm s3-test \
  --image=amazon/aws-cli:latest \
  --serviceaccount=milestone-organizer \
  -n cron-jobs \
  -- s3 ls s3://your-bucket/ --debug 2>&1 | head -50
```

## Post-Deployment Checklist

- [ ] EKS cluster is in ACTIVE state
- [ ] All worker nodes are in Ready state
- [ ] Secrets Store CSI driver installed and running
- [ ] SecretProviderClass manifests created for Vault and GSM
- [ ] CronJob deployed and scheduled
- [ ] IRSA configuration verified
- [ ] Initial CronJob execution successful
- [ ] S3 archival verified
- [ ] CloudWatch logs integration working
- [ ] Monitoring alerts configured (optional)

## Rollback Procedure

### If deployment fails or needs rollback:

```bash
# Delete CronJob
kubectl delete cronjob milestone-organizer -n cron-jobs

# Delete SecretProviderClasses
kubectl delete secretproviderclass vault-database-secrets -n cron-jobs
kubectl delete secretproviderclass gsm-database-secrets -n cron-jobs

# Uninstall Helm charts
helm uninstall secrets-store-csi-driver -n kube-system
helm uninstall vault-secrets-provider -n kube-system

# Drain and delete node group
terraform destroy -auto-approve

# Verify cluster cleanup
kubectl get all -A
```

## Next Steps

1. Set up monitoring and alerting for CronJob failures
2. Configure S3 lifecycle policies for archived data
3. Implement backup strategy for cluster state
4. Set up CloudWatch dashboards for cluster metrics
5. Document custom configurations and local modifications
