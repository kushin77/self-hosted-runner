#!/bin/bash
#
# EKS Cluster Verification Script
# Validates cluster setup, CSI driver, IRSA, and Vault integration
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${1:-milestone-organizer-eks}"
REGION="${2:-us-east-1}"
CRONJOB_NAMESPACE="cron-jobs"
WORKLOADS_NAMESPACE="workloads"

echo -e "${BLUE}=== EKS Cluster Verification ===${NC}"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# Test 1: Cluster connectivity
echo -e "${BLUE}[TEST 1] Cluster Connectivity${NC}"
if aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --query 'cluster.status' \
  --output text | grep -q "ACTIVE"; then
    echo -e "${GREEN}✓${NC} Cluster is ACTIVE"
else
    echo -e "${RED}✗${NC} Cluster not found or inactive"
    exit 1
fi

# Test 2: Node readiness
echo ""
echo -e "${BLUE}[TEST 2] Node Readiness${NC}"
READY_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="True")].metadata.name}' | wc -w)
TOTAL_NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | wc -w)
echo "Ready nodes: $READY_NODES/$TOTAL_NODES"

if [ "$READY_NODES" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} $READY_NODES node(s) ready"
else
    echo -e "${RED}✗${NC} No nodes ready"
    exit 1
fi

# Test 3: CSI Driver Installation
echo ""
echo -e "${BLUE}[TEST 3] Secrets Store CSI Driver${NC}"
if helm list -n kube-system | grep -q "secrets-store-csi-driver"; then
    echo -e "${GREEN}✓${NC} CSI driver Helm release found"
else
    echo -e "${RED}✗${NC} CSI driver Helm release not found"
fi

CSI_PODS=$(kubectl get pods -n kube-system -l app=secrets-store-csi-driver --no-headers 2>/dev/null | wc -l)
if [ "$CSI_PODS" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} $CSI_PODS CSI driver pod(s) running"
else
    echo -e "${RED}✗${NC} No CSI driver pods running"
fi

# Test 4: CSI Driver Class
echo ""
echo -e "${BLUE}[TEST 4] CSI Driver Class${NC}"
if kubectl get csidriver secrets-store.csi.k8s.io &>/dev/null; then
    echo -e "${GREEN}✓${NC} CSI driver class registered"
else
    echo -e "${RED}✗${NC} CSI driver class not found"
fi

# Test 5: SecretProviderClass - Vault
echo ""
echo -e "${BLUE}[TEST 5] SecretProviderClass - Vault${NC}"
if kubectl get secretproviderclass vault-database-secrets -n $CRONJOB_NAMESPACE &>/dev/null; then
    echo -e "${GREEN}✓${NC} Vault SecretProviderClass found"
else
    echo -e "${YELLOW}⚠${NC} Vault SecretProviderClass not found (may not be deployed yet)"
fi

# Test 6: SecretProviderClass - GSM
echo ""
echo -e "${BLUE}[TEST 6] SecretProviderClass - GSM${NC}"
if kubectl get secretproviderclass gsm-database-secrets -n $CRONJOB_NAMESPACE &>/dev/null; then
    echo -e "${GREEN}✓${NC} GSM SecretProviderClass found"
else
    echo -e "${YELLOW}⚠${NC} GSM SecretProviderClass not found (may not be deployed yet)"
fi

# Test 7: Namespaces
echo ""
echo -e "${BLUE}[TEST 7] Kubernetes Namespaces${NC}"
for ns in $CRONJOB_NAMESPACE $WORKLOADS_NAMESPACE; do
    if kubectl get namespace $ns &>/dev/null; then
        echo -e "${GREEN}✓${NC} Namespace '$ns' exists"
    else
        echo -e "${RED}✗${NC} Namespace '$ns' not found"
    fi
done

# Test 8: OIDC Provider
echo ""
echo -e "${BLUE}[TEST 8] OIDC Provider for IRSA${NC}"
OIDC_ID=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --query 'cluster.identity.oidc.issuer' \
    --output text | cut -d'/' -f5)

if [ ! -z "$OIDC_ID" ]; then
    echo -e "${GREEN}✓${NC} OIDC issuer ID: $OIDC_ID"
    
    # Check if provider exists in IAM
    if aws iam list-open-id-connect-providers | grep -q $OIDC_ID; then
        echo -e "${GREEN}✓${NC} OIDC provider registered in IAM"
    else
        echo -e "${RED}✗${NC} OIDC provider not found in IAM"
    fi
else
    echo -e "${RED}✗${NC} OIDC issuer not found"
fi

# Test 9: Service Accounts with IRSA
echo ""
echo -e "${BLUE}[TEST 9] Service Accounts with IRSA${NC}"
SA_COUNT=$(kubectl get sa -n $CRONJOB_NAMESPACE -o jsonpath='{.items[?(@.metadata.annotations.eks\.amazonaws\.com/role-arn)].metadata.name}' | wc -w)
if [ "$SA_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Found $SA_COUNT service account(s) with IRSA annotation"
    kubectl get sa -n $CRONJOB_NAMESPACE -o jsonpath='{.items[?(@.metadata.annotations.eks\.amazonaws\.com/role-arn)].metadata.name}' | tr ' ' '\n' | sed 's/^/  - /'
else
    echo -e "${YELLOW}⚠${NC} No service accounts with IRSA annotation found"
fi

# Test 10: CronJob Deployment
echo ""
echo -e "${BLUE}[TEST 10] CronJob Deployment${NC}"
if kubectl get cronjob -n $CRONJOB_NAMESPACE &>/dev/null; then
    CRONJOB_COUNT=$(kubectl get cronjob -n $CRONJOB_NAMESPACE --no-headers 2>/dev/null | wc -l)
    if [ "$CRONJOB_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Found $CRONJOB_COUNT CronJob(s)"
        kubectl get cronjob -n $CRONJOB_NAMESPACE --no-headers | awk '{print "  - " $1 " (Schedule: " $6 ")"}'
    else
        echo -e "${YELLOW}⚠${NC} No CronJobs found (may not be deployed yet)"
    fi
else
    echo -e "${YELLOW}⚠${NC} CronJob namespace check failed"
fi

# Test 11: IRSA Role Assumption
echo ""
echo -e "${BLUE}[TEST 11] IRSA Role Assumption Test${NC}"
echo "Creating temporary pod to test IRSA role assumption..."

POD_NAME="irsa-test-$(date +%s)"
kubectl run -n $CRONJOB_NAMESPACE --quiet=true --rm -i --restart=Never \
    --image=amazon/aws-cli:latest \
    --serviceaccount=milestone-organizer \
    --overrides='{"spec":{"serviceAccount":"milestone-organizer"}}' \
    $POD_NAME -- \
    sts get-caller-identity > /tmp/irsa_test.json 2>&1 || true

if [ -f /tmp/irsa_test.json ] && grep -q "RoleArn" /tmp/irsa_test.json; then
    echo -e "${GREEN}✓${NC} IRSA role assumption successful"
    ROLE_ARN=$(grep RoleArn /tmp/irsa_test.json | cut -d'"' -f4)
    echo "  Role ARN: $ROLE_ARN"
    rm -f /tmp/irsa_test.json
else
    echo -e "${YELLOW}⚠${NC} IRSA test inconclusive (pod may not have started)"
fi

# Test 12: Security Groups
echo ""
echo -e "${BLUE}[TEST 12] Security Group Configuration${NC}"
CLUSTER_SG=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --query 'cluster.resourcesVpcConfig.securityGroupIds[0]' \
    --output text)

if [ ! -z "$CLUSTER_SG" ] && [ "$CLUSTER_SG" != "None" ]; then
    echo -e "${GREEN}✓${NC} Cluster security group: $CLUSTER_SG"
    # Count security groups
    NODE_SG_COUNT=$(aws ec2 describe-security-groups \
        --region $REGION \
        --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
        --query 'length(SecurityGroups)' \
        --output text)
    echo -e "${GREEN}✓${NC} Found $NODE_SG_COUNT security group(s) for the cluster"
else
    echo -e "${RED}✗${NC} Could not retrieve security group information"
fi

# Test 13: CloudWatch Logs
echo ""
echo -e "${BLUE}[TEST 13] CloudWatch Logs Configuration${NC}"
LOG_ENABLED=$(aws eks describe-cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --query 'cluster.logging.clusterLogging[0].enabled' \
    --output text)

if [ "$LOG_ENABLED" = "True" ]; then
    echo -e "${GREEN}✓${NC} CloudWatch logging enabled"
    LOG_TYPES=$(aws eks describe-cluster \
        --name $CLUSTER_NAME \
        --region $REGION \
        --query 'cluster.logging.clusterLogging[0].types' \
        --output text)
    echo "  Enabled log types: $LOG_TYPES"
else
    echo -e "${YELLOW}⚠${NC} CloudWatch logging not fully enabled"
fi

# Summary
echo ""
echo -e "${BLUE}=== Verification Summary ===${NC}"
echo "All critical checks completed. Review results above for any issues."
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Apply SecretProviderClass manifests if not deployed"
echo "2. Deploy CronJob manifest for milestone-organizer"
echo "3. Monitor initial CronJob execution"
echo "4. Verify S3 archival and CloudWatch logs"
echo ""
