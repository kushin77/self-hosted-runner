#!/bin/bash
#
# EKS Deployment Quick Start
# Fast-track deployment for milestone organizer EKS cluster
#

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   EKS Deployment Quick Start - 5 Minute Setup             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Environment Configuration
echo -e "${BLUE}[STEP 1/5] Configure Environment${NC}"
echo ""
echo "Enter the following information:"
read -p "AWS Region (default: us-east-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

read -p "Cluster Name (default: milestone-organizer-eks): " CLUSTER_NAME
CLUSTER_NAME=${CLUSTER_NAME:-milestone-organizer-eks}

read -p "VPC ID: " VPC_ID
read -p "Private Subnet IDs (comma-separated): " SUBNET_IDS

read -p "S3 Bucket Name: " S3_BUCKET
read -p "Container Image: " CONTAINER_IMAGE

export AWS_REGION CLUSTER_NAME VPC_ID S3_BUCKET CONTAINER_IMAGE

echo -e "${GREEN}✓ Environment configured${NC}"
echo ""

# Step 2: Prerequisite Check
echo -e "${BLUE}[STEP 2/5] Check Prerequisites${NC}"

MISSING_TOOLS=0

for tool in aws terraform kubectl helm; do
    if command -v $tool &> /dev/null; then
        echo -e "${GREEN}✓${NC} $tool found"
    else
        echo -e "${RED}✗${NC} $tool not found. Please install it."
        MISSING_TOOLS=1
    fi
done

if [ $MISSING_TOOLS -eq 1 ]; then
    echo -e "${RED}Please install missing tools and try again.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites available${NC}"
echo ""

# Step 3: Terraform Deployment
echo -e "${BLUE}[STEP 3/5] Deploy EKS Cluster with Terraform${NC}"

cd /home/akushnir/self-hosted-runner/terraform

# Create tfvars file
cat > quick-start.tfvars <<EOF
cluster_name       = "$CLUSTER_NAME"
cluster_version    = "1.29"
region             = "$AWS_REGION"
vpc_id             = "$VPC_ID"
subnet_ids         = ["$VPC_ID"]  # Replace with actual public subnet
private_subnet_ids = [
  $(echo $SUBNET_IDS | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')
]

desired_size       = 3
min_size           = 1
max_size           = 10
instance_types     = ["t3.xlarge"]
disk_size          = 100
enable_ssm_access  = true

vault_address      = ""  # Leave empty or set to your Vault address
vault_namespace    = ""

enable_secrets_store_csi = true
csi_driver_version = "v1.3.4"

tags = {
  Environment = "production"
  Project     = "milestone-organizer"
  ManagedBy   = "terraform"
}
EOF

echo "Initializing Terraform..."
terraform init

echo "Planning deployment..."
terraform plan -out=quick-start.plan -var-file=quick-start.tfvars

echo ""
echo -e "${YELLOW}Review the plan above. Enter 'yes' to continue with deployment.${NC}"
read -p "Continue with Terraform apply? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Deployment cancelled.${NC}"
    exit 0
fi

echo "Applying Terraform configuration..."
terraform apply quick-start.plan

echo -e "${GREEN}✓ EKS cluster deployed${NC}"
echo ""

# Step 4: Configure kubectl
echo -e "${BLUE}[STEP 4/5] Configure kubectl Access${NC}"

aws eks update-kubeconfig \
    --region $AWS_REGION \
    --name $CLUSTER_NAME

echo "Waiting for cluster to be fully ready..."
kubectl wait nodes --for=condition=Ready --all --timeout=300s || true

echo -e "${GREEN}✓ kubectl configured${NC}"
echo ""

# Step 5: Deploy CronJob
echo -e "${BLUE}[STEP 5/5] Deploy CronJob${NC}"

bash /home/akushnir/self-hosted-runner/deploy/milestone-organizer-deploy-and-test.sh

echo ""
echo -e "${GREEN}✓ CronJob deployed and tested${NC}"
echo ""

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Deployment Complete!                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Cluster Details:"
echo "  Name: $CLUSTER_NAME"
echo "  Region: $AWS_REGION"
echo "  URL: $(kubectl cluster-info | grep 'Kubernetes master')"
echo ""
echo "Node Status:"
kubectl get nodes
echo ""
echo "CronJob Status:"
kubectl get cronjobs -n cron-jobs
echo ""
echo "Next Steps:"
echo "  1. Monitor logs: kubectl logs -f -n cron-jobs deployment/milestone-organizer"
echo "  2. Check S3: aws s3 ls s3://$S3_BUCKET/milestone-organizer/"
echo "  3. View events: kubectl describe cronjob milestone-organizer -n cron-jobs"
echo ""
echo "Documentation:"
echo "  - Full Guide: /home/akushnir/self-hosted-runner/EKS_IMPLEMENTATION_GUIDE.md"
echo "  - Bootstrap Runbook: /home/akushnir/self-hosted-runner/EKS_CLUSTER_BOOTSTRAP_RUNBOOK.md"
echo "  - Module README: /home/akushnir/self-hosted-runner/terraform/modules/eks/README.md"
echo ""
