# Azure Scale Set Runner Migration Guide

This guide provides step-by-step instructions for migrating GitHub Actions workflows from GitHub-hosted runners or other self-hosted runner platforms to Azure Virtual Machine Scale Sets.

## Table of Contents

- [Pre-Migration Checklist](#pre-migration-checklist)
- [Phase 1: Preparation](#phase-1-preparation)
- [Phase 2: Terraform Deployment](#phase-2-terraform-deployment)
- [Phase 3: Runner Registration](#phase-3-runner-registration)
- [Phase 4: Workflow Migration](#phase-4-workflow-migration)
- [Phase 5: Validation and Cutover](#phase-5-validation-and-cutover)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

---

## Pre-Migration Checklist

Before starting migration, verify:

- [ ] Azure subscription access and appropriate permissions
- [ ] Azure Resource Group created and accessible
- [ ] SSH key pair generated for VM access
- [ ] GitHub organization/repository tokens available
- [ ] Terraform and Azure CLI installed locally
- [ ] Network connectivity to Azure region confirmed
- [ ] Capacity requirements calculated (see Capacity Planning Guide)
- [ ] Budget approved for Azure infrastructure
- [ ] Staging environment available for testing
- [ ] Stakeholders notified of planned migration

---

## Phase 1: Preparation

### 1.1 Gather Infrastructure Requirements

Determine what you need:

```bash
# Export current GitHub runner labels
gh api repos/{owner}/{repo}/actions/runners --jq '.runners[].labels[].name' | sort | uniq

# Document runner requirements
cat > runner-requirements.md << 'EOF'
## Runner Requirements

### Labels
- linux
- ubuntu-latest
- docker
- 4core (custom)

### Performance Needs
- 4 vCPUs minimum
- 16GB RAM for builds
- Docker support required
- SSD for build cache

### Concurrent Jobs
- Peak: 20 simultaneous jobs
- Minimum capacity: 10 instances
- Maximum capacity: 50 instances with autoscaling
EOF
```

### 1.2 Create Azure Resources

```bash
# Set variables
RESOURCE_GROUP="github-runners-prod"
LOCATION="eastus"
SUBSCRIPTION_ID="your-subscription-id"

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Create storage account for terraform state (optional)
az storage account create \
  --name "tfrstate$(date +%s)" \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS

# Grant yourself access if needed
az role assignment create \
  --role "Virtual Machine Contributor" \
  --assignee $(az ad signed-in-user show --query objectId -o tsv) \
  --resource-group $RESOURCE_GROUP
```

### 1.3 Generate SSH Key

```bash
# Generate SSH keypair if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_runner_key -N ""

# Display public key for Terraform
cat ~/.ssh/azure_runner_key.pub

# Store public key in secure location
echo "Azure Runner SSH Public Key:" > /tmp/runner_ssh_key.pub
cat ~/.ssh/azure_runner_key.pub >> /tmp/runner_ssh_key.pub
```

---

## Phase 2: Terraform Deployment

### 2.1 Prepare Terraform Configuration

Navigate to the Azure scale set example directory:

```bash
cd terraform/examples/azure-scale/

# Create terraform.tfvars with your specific values
cat > terraform.tfvars << 'EOF'
resource_group_name = "github-runners-prod"
location             = "eastus"
vm_sku               = "Standard_D4s_v3"        # Adjust based on needs
capacity             = 10                       # Initial capacity
admin_username       = "azurerunner"
admin_ssh_public_key = "ssh-rsa AAAA... your-public-key ..."

# Optional: Override defaults
# enable_autoscaling = true
# min_capacity = 5
# max_capacity = 50
# environment = "production"
# runner_labels = ["azure", "production", "linux", "docker"]
# runner_group = "prod-azure"
EOF
```

### 2.2 Initialize and Plan

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Generate and review plan
terraform plan -out=tfplan

# Review resources that will be created
terraform show tfplan | grep 'azurerm_'
```

### 2.3 Deploy Infrastructure

```bash
# Create resources (takes 5-15 minutes)
terraform apply tfplan

# Capture outputs
terraform output -json > runner-outputs.json

# Verify deployment
az vmss list --resource-group github-runners-prod --query '[].{name:name, capacity:sku.capacity}' -o table
```

### 2.4 Verify VM Connectivity

```bash
# Get scale set details
VMSS_NAME=$(terraform output vmss_name | tr -d '"')
RESOURCE_GROUP=$(terraform output -json | jq -r '.vmss_id.value' | grep -oP 'resourceGroups/\K[^/]+')

# Get IP addresses of instances
az vmss list-instance-connection-info \
  --resource-group $RESOURCE_GROUP \
  --name $VMSS_NAME

# Test SSH connectivity
# SSH_KEY="${HOME}/.ssh/azure_runner_key"
# SSH_CONNECTION="azurerunner@public_ip -i $SSH_KEY"
# ssh -o StrictHostKeyChecking=no $SSH_CONNECTION "echo 'Connection successful'"
```

---

## Phase 3: Runner Registration

### 3.1 Obtain GitHub Actions Token

```bash
# Create personal access token with 'admin:org' scope for organization runners
# or 'repo' scope for repository runners
gh auth login --scopes admin:org

# For organization runners
ORG="your-organization"
RUNNER_GROUP="azure-prod"
```

### 3.2 Prepare Runner Registration Script

```bash
# Create runner registration script
cat > /tmp/register-runner.sh << 'EOF'
#!/bin/bash
set -e

# Configuration
RUNNER_VERSION="2.317.0"  # Check latest version
REGISTRATION_TOKEN="$1"   # Pass as argument
RUNNER_GROUP="$2"
LABELS="$3"

# Install runner
cd /home/runner
curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
  -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

tar xzf actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Configure runner
./config.sh \
  --url https://github.com/${ORG} \
  --token ${REGISTRATION_TOKEN} \
  --name "azure-runner-$(hostname)" \
  --runnergroup "${RUNNER_GROUP}" \
  --labels "${LABELS}" \
  --unattended \
  --replace

# Install and start service
sudo ./svc.sh install
sudo ./svc.sh start
EOF

chmod +x /tmp/register-runner.sh
```

### 3.3 Push Registration Script to VMs

```bash
#  Deploy registration script to scale set instances
VMSS_NAME=$(terraform output vmss_name | tr -d '"')
RESOURCE_GROUP="github-runners-prod"

# Create custom data with registration
cat > custom-data.sh << EOF
#!/bin/bash
set -e

# System setup
apt-get update && apt-get upgrade -y
apt-get install -y curl wget git jq

# Create runner user
useradd -m -s /bin/bash runner || true
usermod -aG sudo runner || true

# Install runner and start service
su - runner << 'RUNNER_EOF'
mkdir -p /home/runner
cd /home/runner

# Download latest runner release
RUNNER_VERSION=\$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/^v//')

curl -o actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz -L \\
  https://github.com/actions/runner/releases/download/v\${RUNNER_VERSION}/actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz

tar xzf actions-runner-linux-x64-\${RUNNER_VERSION}.tar.gz

# Configure (will use env variables from Azure)
./config.sh \\
  --url https://github.com/${ORG} \\
  --token ${REGISTRATION_TOKEN} \\
  --name "azure-\$(hostname)" \\
  --runnergroup "${RUNNER_GROUP}" \\
  --labels "${LABELS}" \\
  --unattended \\
  --replace

# Start service
sudo ./svc.sh install
sudo ./svc.sh start
RUNNER_EOF
EOF
```

### 3.4 Update Scale Set with Runner Configuration

For production deployment, use GitHub's official actions/setup-actions-runner or deploy runners manually to each instance:

```bash
# Option 1: Manual setup (for testing)
# SSH into each instance and run setup commands

# Option 2: Custom script in Terraform
# Include registration script in custom_script_command variable

# Option 3: Use GitHub's official runner container image
# Deploy as container in VMSS
```

---

## Phase 4: Workflow Migration

### 4.1 Update Workflow Files

Change workflow `runs-on` to use new Azure runners:

**Before:**
```yaml
jobs:
  build:
    runs-on: ubuntu-latest  # GitHub-hosted runner
```

**After:**
```yaml
jobs:
  build:
    runs-on: [self-hosted, linux, docker, azure]  # Azure runner with labels
```

### 4.2 Create Test Workflow

```yaml
name: Test Azure Runner
on: [push]

jobs:
  test:
    runs-on: [self-hosted, linux, azure]
    steps:
      - uses: actions/checkout@v4
      
      - name: Check runner environment
        run: |
          echo "Runner: $(hostname)"
          echo "OS: $(uname -a)"
          echo "CPUs: $(nproc)"
          echo "Memory: $(free -h)"
          
      - name: Test Docker
        run: docker run --rm hello-world
      
      - name: Run tests
        run: |
          # Your test commands
          make test
```

### 4.3 Gradual Workflow Migration

Migrate workflows gradually:

1. **Week 1:** Test workflows only
   - Deploy test job on Azure runners
   - Monitor and validate
   
2. **Week 2:** Non-critical workflows
   - Migrate lower-priority CI jobs
   - Maintain GitHub-hosted fallback
   
3. **Week 3:** Critical workflows
   - Migrate all production CI
   - Monitor performance
   
4. **Week 4:** Decommission old runners
   - Verify all jobs migrated
   - Clean up GitHub-hosted runners if applicable

---

## Phase 5: Validation and Cutover

### 5.1 Pre-Cutover Validation

```bash
# Verify runner connectivity
gh api orgs/{org}/actions/runners --jq '.runners[] | select(.name | contains("azure")) | {name, status, busy}'

# Check run history
gh run list --repo owner/repo --limit 50 | grep -i azure

# Validate performance
# Compare job duration before/after migration
gh api repos/{owner}/{repo}/actions/runs?status=completed | jq '.workflow_runs[] | {conclusion, run_number, updated_at}' | head -20
```

### 5.2 Load Testing

```bash
# Submit parallel test jobs to verify autoscaling
for i in {1..30}; do
  gh workflow run test-azure-runner.yml &
done
wait

# Monitor scaling events
az monitor metrics list-definitions \
  --resource /subscriptions/{id}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachineScaleSets/{vmss} \
  --query "value[?name.value=='Percentage CPU'].name.value" -o tsv
```

### 5.3 Performance Baseline

Establish baseline metrics:

```bash
# Document baseline
cat > baseline-metrics.md << 'EOF'
## Azure Runner Performance Baseline

### Metrics (from first 30 days)
- Average job duration: X minutes
- P95 job duration: Y minutes
- Success rate: Z%
- Queue wait time: W seconds

### Capacity Utilization
- Average: N%
- Peak: M%
- Autoscaling events: K per day

### Cost
- Monthly estimate: $X
- Cost per job: $Y
EOF
```

### 5.4 Cutover Decision

Proceed to full cutover when:

- ✓ All test workflows passing on Azure
- ✓ Performance meets or exceeds requirements
- ✓ No critical issues in staging (1+ week)
- ✓ Team trained on new infrastructure
- ✓ Runbooks documented
- ✓ Rollback plan verified

---

## Rollback Procedures

### Quick Rollback (< 2 hours)

If critical issues occur:

```bash
# 1. Update workflows to use GitHub-hosted runners
#    (git revert, pr merge, close issue)

# 2. Stop accepting new jobs on Azure runners
az vmss scale \
  --resource-group github-runners-prod \
  --name runner-vmss \
  --new-capacity 0

# 3. Monitor for job completions
gh run list --repo owner/repo --limit 100

# 4. Verify GitHub-hosted runners are operational
```

### Full Teardown (if rejecting Azure entirely)

```bash
# Destroy all Azure resources
cd terraform/examples/azure-scale/
terraform destroy -auto-approve

# Verify cleanup
az vmss list --resource-group github-runners-prod
az group delete --name github-runners-prod
```

### Partial Rollback (keep Azure, revert specific workflows)

```bash
# Revert workflow changes in git
git revert <commit-hash>
git push origin main

# Keep Azure runners running for other workflows
```

---

## Troubleshooting

### Problem: Runners not connecting to GitHub

```bash
# Check runner status on VMs
ssh azurerunner@<instance-ip>
cd /home/runner/runner-application
tail -f .runner
nano ../.runner

# Verify registration token
# Registration tokens expire after 1 hour - get fresh token if needed
gh api organizations/{org}/actions/runners/registration-token

# Check GitHub runner logs
```

### Problem: Jobs queuing (not running)

```bash
# Check runner capacity
gh api orgs/{org}/actions/runners?per_page=100 | jq '.runners | length'

# Check busy runners
gh api orgs/{org}/actions/runners | jq '.runners[] | select(.busy==true) | {name, busy}'

# Increase scale set capacity
az vmss scale \
  --resource-group github-runners-prod \
  --name runner-vmss \
  --new-capacity 25
```

### Problem: High job failure rate

```bash
# SSH to instance and check logs
ssh azurerunner@<instance-ip>

# Check system resources
top
df -h
free -h

# Check Docker daemon
docker ps
docker logs

# Increase min_capacity if memory/cpu constrained
terraform apply -var min_capacity=15
```

### Problem: Cost overrun

```bash
# Check scaling events
az monitor metrics list \
  --resource /subscriptions/{id}/resourceGroups/github-runners-prod/providers/Microsoft.Compute/virtualMachineScaleSets/runner-vmss \
  --metric "VMScalingEvents"

# Adjust autoscaling thresholds
# Reduce max_capacity
# Enable scheduled scale-down during off-hours
```

---

## Support

For issues or questions:

1. Check [Azure Scale Set Capacity Planning Guide](./AZURE_SCALE_SET_CAPACITY_PLANNING.md)
2. Review [Terraform module documentation](../terraform/modules/azure_scale_set/README.md)
3. Consult [GitHub Actions documentation](https://docs.github.com/en/actions)
4. Check Azure diagnostics and monitoring

---

**Document Version:** 1.0  
**Last Updated:** March 2026  
**Maintained by:** Infrastructure Team
