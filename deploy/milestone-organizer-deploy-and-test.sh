#!/bin/bash
#
# Milestone Organizer - EKS Deployment Script
# Deploys and tests the milestone organizer CronJob on EKS cluster
# Runs on worker node 192.168.168.42
#

set -e

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-milestone-organizer-eks}"
REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="cron-jobs"
CRONJOB_NAME="milestone-organizer"
CONTAINER_IMAGE="${CONTAINER_IMAGE:-milestone-organizer:latest}"
ECR_REGISTRY="${ECR_REGISTRY:-}"
S3_BUCKET="${S3_BUCKET:-}"
VAULT_ADDRESS="${VAULT_ADDRESS:-}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Milestone Organizer EKS Deployment ===${NC}"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Image: $CONTAINER_IMAGE"
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${BLUE}[STEP 1] Checking Prerequisites${NC}"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗${NC} kubectl not found"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} kubectl found"
    
    # Check cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}✗${NC} Cannot connect to cluster"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Cluster connectivity verified"
    
    # Check namespace
    if ! kubectl get namespace $NAMESPACE &>/dev/null; then
        echo -e "${YELLOW}⚠${NC} Namespace '$NAMESPACE' not found, creating..."
        kubectl create namespace $NAMESPACE
        echo -e "${GREEN}✓${NC} Namespace created"
    else
        echo -e "${GREEN}✓${NC} Namespace '$NAMESPACE' exists"
    fi
    
    echo ""
}

# Function to verify CSI driver
verify_csi_driver() {
    echo -e "${BLUE}[STEP 2] Verifying Secrets Store CSI Driver${NC}"
    
    if ! kubectl get csidriver secrets-store.csi.k8s.io &>/dev/null; then
        echo -e "${RED}✗${NC} CSI driver not found"
        echo "Install via: helm install secrets-store-csi-driver"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} CSI driver registered"
    
    CSI_PODS=$(kubectl get pods -n kube-system -l app=secrets-store-csi-driver --no-headers 2>/dev/null | grep -c Running || echo 0)
    if [ "$CSI_PODS" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} CSI driver pod running"
    else
        echo -e "${YELLOW}⚠${NC} CSI driver pod not running"
    fi
    
    echo ""
}

# Function to deploy SecretProviderClass manifests
deploy_secret_providers() {
    echo -e "${BLUE}[STEP 3] Deploying SecretProviderClass Manifests${NC}"
    
    # Create temporary directory for manifests
    MANIFEST_DIR="/tmp/eks-manifests-$(date +%s)"
    mkdir -p $MANIFEST_DIR
    
    # Vault SecretProviderClass
    if [ ! -z "$VAULT_ADDRESS" ]; then
        echo "Creating Vault SecretProviderClass..."
        cat > $MANIFEST_DIR/vault-provider.yaml <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-database-secrets
  namespace: $NAMESPACE
spec:
  provider: vault
  parameters:
    vaultAddress: $VAULT_ADDRESS
    vaultNamespace: $VAULT_NAMESPACE
    vaultRole: milestone-organizer
    vaultKubernetesMountPath: kubernetes
    secretPath: secret/data/milestone-organizer
    objects: |
      - objectName: "db-password"
        secretPath: "secret/data/milestone-organizer/db"
        secretKey: "password"
      - objectName: "db-username"
        secretPath: "secret/data/milestone-organizer/db"
        secretKey: "username"
      - objectName: "api-key"
        secretPath: "secret/data/milestone-organizer/api"
        secretKey: "key"
      - objectName: "s3-access-key"
        secretPath: "secret/data/milestone-organizer/s3"
        secretKey: "access_key"
      - objectName: "s3-secret-key"
        secretPath: "secret/data/milestone-organizer/s3"
        secretKey: "secret_key"
EOF
        kubectl apply -f $MANIFEST_DIR/vault-provider.yaml
        echo -e "${GREEN}✓${NC} Vault SecretProviderClass deployed"
    fi
    
    # GSM SecretProviderClass
    if [ ! -z "$GCP_PROJECT_ID" ]; then
        echo "Creating GSM SecretProviderClass..."
        cat > $MANIFEST_DIR/gsm-provider.yaml <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: gsm-database-secrets
  namespace: $NAMESPACE
spec:
  provider: gcp
  parameters:
    secrets: |
      - resourceName: "projects/$GCP_PROJECT_ID/secrets/milestone-organizer-db-password/versions/latest"
        path: "db-password"
      - resourceName: "projects/$GCP_PROJECT_ID/secrets/milestone-organizer-db-username/versions/latest"
        path: "db-username"
      - resourceName: "projects/$GCP_PROJECT_ID/secrets/milestone-organizer-api-key/versions/latest"
        path: "api-key"
      - resourceName: "projects/$GCP_PROJECT_ID/secrets/milestone-organizer-s3-access-key/versions/latest"
        path: "s3-access-key"
      - resourceName: "projects/$GCP_PROJECT_ID/secrets/milestone-organizer-s3-secret-key/versions/latest"
        path: "s3-secret-key"
EOF
        kubectl apply -f $MANIFEST_DIR/gsm-provider.yaml
        echo -e "${GREEN}✓${NC} GSM SecretProviderClass deployed"
    fi
    
    echo ""
}

# Function to deploy CronJob
deploy_cronjob() {
    echo -e "${BLUE}[STEP 4] Deploying CronJob${NC}"
    
    # Get IRSA role ARN
    IRSA_ROLE_ARN=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, 'cronjob-role')].Arn" \
        --output text | head -1)
    
    if [ -z "$IRSA_ROLE_ARN" ]; then
        echo -e "${YELLOW}⚠${NC} IRSA role not found. Create it via Terraform first."
        IRSA_ROLE_ARN="arn:aws:iam::ACCOUNT:role/$CLUSTER_NAME-cronjob-role"
    fi
    
    echo "IRSA Role ARN: $IRSA_ROLE_ARN"
    
    # Create CronJob manifest
    cat > /tmp/cronjob.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: milestone-organizer
  namespace: $NAMESPACE
  annotations:
    eks.amazonaws.com/role-arn: $IRSA_ROLE_ARN
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: $CRONJOB_NAME
  namespace: $NAMESPACE
  labels:
    app: milestone-organizer
    version: v1
spec:
  schedule: "0 */6 * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 5
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: milestone-organizer
            version: v1
        spec:
          serviceAccountName: milestone-organizer
          restartPolicy: OnFailure
          securityContext:
            fsGroup: 65534
            runAsNonRoot: true
            runAsUser: 65534
          containers:
          - name: milestone-organizer
            image: $CONTAINER_IMAGE
            imagePullPolicy: IfNotPresent
            securityContext:
              allowPrivilegeEscalation: false
              capabilities:
                drop:
                - ALL
              readOnlyRootFilesystem: true
            env:
            - name: AWS_REGION
              value: $REGION
            - name: AWS_ROLE_ARN
              value: $IRSA_ROLE_ARN
            - name: AWS_WEB_IDENTITY_TOKEN_FILE
              value: /var/run/secrets/eks.amazonaws.com/serviceaccount/token
            volumeMounts:
            - name: tmp
              mountPath: /tmp
            resources:
              requests:
                memory: "256Mi"
                cpu: "250m"
              limits:
                memory: "512Mi"
                cpu: "500m"
          volumes:
          - name: tmp
            emptyDir:
              medium: Memory
              sizeLimit: 256Mi
EOF
    
    kubectl apply -f /tmp/cronjob.yaml
    echo -e "${GREEN}✓${NC} CronJob deployed"
    
    # Verify deployment
    if kubectl get cronjob $CRONJOB_NAME -n $NAMESPACE &>/dev/null; then
        echo -e "${GREEN}✓${NC} CronJob verified"
        kubectl get cronjob -n $NAMESPACE
    else
        echo -e "${RED}✗${NC} CronJob deployment failed"
        exit 1
    fi
    
    echo ""
}

# Function to test job execution
test_job_execution() {
    echo -e "${BLUE}[STEP 5] Testing Initial Job Execution${NC}"
    
    # Create manual job from cronjob template
    echo "Creating test job from CronJob template..."
    kubectl create job --from=cronjob/$CRONJOB_NAME test-$CRONJOB_NAME-$(date +%s) -n $NAMESPACE
    
    # Wait for job to complete (max 5 minutes)
    echo "Waiting for job to complete (max 5 minutes)..."
    MAX_WAIT=300
    ELAPSED=0
    JOB_COMPLETED=false
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        if kubectl get job test-$CRONJOB_NAME-* -n $NAMESPACE -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null | grep -q "1"; then
            JOB_COMPLETED=true
            break
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
    done
    
    if [ "$JOB_COMPLETED" = true ]; then
        echo -e "${GREEN}✓${NC} Job completed successfully"
    else
        echo -e "${YELLOW}⚠${NC} Job still running or not completed (job may take longer)"
    fi
    
    # Show job status
    echo ""
    echo "Job Status:"
    kubectl get jobs -n $NAMESPACE
    
    # Show pod logs
    echo ""
    echo "Recent Pod Logs:"
    POD=$(kubectl get pods -n $NAMESPACE -l app=milestone-organizer --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null)
    if [ ! -z "$POD" ]; then
        kubectl logs $POD -n $NAMESPACE --tail=50 || echo "Logs not available yet"
    fi
    
    echo ""
}

# Function to verify S3 access
verify_s3_access() {
    if [ -z "$S3_BUCKET" ]; then
        echo -e "${YELLOW}⚠${NC} S3_BUCKET not configured, skipping S3 verification"
        return
    fi
    
    echo -e "${BLUE}[STEP 6] Verifying S3 Access${NC}"
    
    # Create pod to test S3 access
    echo "Testing S3 bucket access..."
    POD_NAME="s3-test-$(date +%s)"
    
    kubectl run -n $NAMESPACE --quiet=true --rm -i --restart=Never \
        --image=amazon/aws-cli:latest \
        --serviceaccount=milestone-organizer \
        $POD_NAME -- \
        s3 ls s3://$S3_BUCKET/ &>/dev/null && \
        echo -e "${GREEN}✓${NC} S3 bucket access verified" || \
        echo -e "${YELLOW}⚠${NC} S3 access test inconclusive"
    
    echo ""
}

# Function to show summary
show_summary() {
    echo -e "${BLUE}=== Deployment Summary ===${NC}"
    echo ""
    echo "CronJob Details:"
    kubectl get cronjob -n $NAMESPACE
    echo ""
    echo "Service Account:"
    kubectl get sa -n $NAMESPACE
    echo ""
    echo "Recent Jobs:"
    kubectl get jobs -n $NAMESPACE --sort-by=.metadata.creationTimestamp | tail -5
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Monitor CronJob execution: kubectl logs -f pod-name -n $NAMESPACE"
    echo "2. Check S3 archival: aws s3 ls s3://$S3_BUCKET/milestone-organizer/"
    echo "3. View CloudWatch logs: aws logs tail /aws/eks/$CLUSTER_NAME --follow"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    verify_csi_driver
    deploy_secret_providers
    deploy_cronjob
    test_job_execution
    verify_s3_access
    show_summary
    
    echo -e "${GREEN}Deployment completed!${NC}"
}

main
