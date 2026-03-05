# Deploying Runners on Google Cloud Platform (Compute Engine)

## Overview

This guide deploys self-provisioning runners on GCP Compute Engine using startup scripts. Runners auto-register with GitHub and self-heal automatically.

## Prerequisites

- GCP project with Compute Engine API enabled
- `gcloud` CLI installed and authenticated
- GitHub Personal Access Token (PAT) with `admin:self_hosted_runner` scope
- Service account with Compute Engine permissions

## Step 1: Create Service Account

```bash
#!/usr/bin/env bash
# create-service-account.sh

PROJECT_ID="my-project"
SA_NAME="github-runner"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Create service account
gcloud iam service-accounts create ${SA_NAME} \
  --display-name="GitHub Actions Runner" \
  --project=${PROJECT_ID}

# Grant permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.instanceAdmin.v1"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"

echo "✓ Service account created: ${SA_EMAIL}"
```

## Step 2: Create Custom Machine Image

```bash
#!/usr/bin/env bash
# create-image.sh

PROJECT_ID="my-project"
IMAGE_NAME="github-runner-image"
ZONE="us-central1-a"
INSTANCE_NAME="github-runner-builder"

# Create builder instance
gcloud compute instances create ${INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --zone=${ZONE} \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --machine-type=e2-medium \
  --scopes=cloud-platform \
  --metadata-from-file startup-script=bootstrap-startup-script.sh

# Wait for bootstrap to complete (check logs)
echo "Waiting for bootstrap to complete..."
sleep 180

# Create image from instance
gcloud compute images create ${IMAGE_NAME} \
  --source-disk=${INSTANCE_NAME} \
  --source-disk-zone=${ZONE} \
  --family=github-runner

# Stop and delete builder instance
gcloud compute instances delete ${INSTANCE_NAME} --zone=${ZONE}

echo "✓ Custom image created: ${IMAGE_NAME}"
```

## Step 3: Store Secret in Secret Manager

```bash
#!/usr/bin/env bash
# store-token.sh

PROJECT_ID="my-project"
GITHUB_TOKEN="ghr_xxxxxxxxxxxxxxxx"
SECRET_NAME="github-runner-token"

# Create secret
echo -n "${GITHUB_TOKEN}" | gcloud secrets create ${SECRET_NAME} \
  --project=${PROJECT_ID} \
  --data-file=- \
  --replication-policy="automatic"

echo "✓ Token stored in Secret Manager: projects/${PROJECT_ID}/secrets/${SECRET_NAME}"
```

## Step 4: Create Startup Script

Create `bootstrap-startup-script.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="my-project"
SECRET_NAME="github-runner-token"
RUNNER_URL="https://github.com/YOUR_ORG"
RUNNER_LABELS="gcp,compute-engine,linux,docker"

# Get token from Secret Manager
GITHUB_TOKEN=$(gcloud secrets versions access latest --secret=${SECRET_NAME} --project=${PROJECT_ID})

# Clone and bootstrap
git clone https://github.com/YOUR_ORG/self-hosted-runner /opt/runner-platform
cd /opt/runner-platform/bootstrap

export RUNNER_TOKEN="${GITHUB_TOKEN}"
export RUNNER_URL="${RUNNER_URL}"
export RUNNER_LABELS="${RUNNER_LABELS}"

sudo bash bootstrap.sh

# Setup daemons
sudo bash setup-daemons.sh

# Report to Cloud Logging
echo "Runner bootstrap complete" | gcloud logging write runner-bootstrap "Bootstrap completed" --severity=INFO
```

## Step 5: Create Instance Template

```bash
#!/usr/bin/env bash
# create-instance-template.sh

PROJECT_ID="my-project"
TEMPLATE_NAME="github-runner-template"
IMAGE_NAME="github-runner-image"
NETWORK_NAME="default"
SUBNET_NAME="default"
SERVICE_ACCOUNT_EMAIL="github-runner@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud compute instance-templates create ${TEMPLATE_NAME} \
  --project=${PROJECT_ID} \
  --machine-type=e2-standard-2 \
  --image-family=github-runner \
  --image-project=${PROJECT_ID} \
  --scopes=cloud-platform \
  --service-account=${SERVICE_ACCOUNT_EMAIL} \
  --metadata-from-file startup-script=bootstrap-startup-script.sh \
  --boot-disk-size=100GB \
  --boot-disk-type=pd-ssd \
  --labels=app=github-runner,environment=production \
  --network-interface=network-tier=PREMIUM,subnet=${SUBNET_NAME}

echo "✓ Instance template created: ${TEMPLATE_NAME}"
```

## Step 6: Create Instance Group

```bash
#!/usr/bin/env bash
# create-instance-group.sh

PROJECT_ID="my-project"
REGION="us-central1"
IG_NAME="github-runners-ig"
TEMPLATE_NAME="github-runner-template"

# Create managed instance group
gcloud compute instance-groups managed create ${IG_NAME} \
  --project=${PROJECT_ID} \
  --region=${REGION} \
  --template=${TEMPLATE_NAME} \
  --size=3 \
  --initial-delay-sec=300

# Create autoscaler
gcloud compute instance-groups managed set-autoscaling ${IG_NAME} \
  --project=${PROJECT_ID} \
  --region=${REGION} \
  --max-num-replicas=10 \
  --min-num-replicas=1 \
  --target-cpu-utilization=0.7

echo "✓ Instance group created: ${IG_NAME}"
```

## Step 7: Configure Firewall Rules

```bash
#!/usr/bin/env bash
# create-firewall.sh

PROJECT_ID="my-project"

# Allow egress to GitHub (HTTPS)
gcloud compute firewall-rules create allow-github-api \
  --project=${PROJECT_ID} \
  --direction=EGRESS \
  --priority=1000 \
  --destination-ranges=0.0.0.0/0 \
  --allow=tcp:443 \
  --target-tags=github-runner

# Deny all other egress (except DNS)
gcloud compute firewall-rules create deny-all-egress \
  --project=${PROJECT_ID} \
  --direction=EGRESS \
  --priority=10000 \
  --destination-ranges=0.0.0.0/0 \
  --allow=tcp:53,udp:53 \
  --target-tags=github-runner

echo "✓ Firewall rules configured"
```

## Step 8: Monitoring & Logging

```bash
#!/usr/bin/env bash
# setup-monitoring.sh

PROJECT_ID="my-project"

# Create log sink for runner logs
gcloud logging sinks create github-runner-logs \
  --project=${PROJECT_ID} \
  logging.googleapis.com/projects/${PROJECT_ID}/logs/github-runner

# Create alert policy for high CPU
cat > /tmp/alert-policy.json <<EOF
{
  "displayName": "GitHub Runner High CPU",
  "conditions": [{
    "displayName": "CPU > 80%",
    "conditionThreshold": {
      "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_group=\"github-runners-ig\"",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 0.8,
      "duration": "300s"
    }
  }]
}
EOF

gcloud alpha monitoring policies create --policy-from-file=/tmp/alert-policy.json \
  --project=${PROJECT_ID}

echo "✓ Monitoring configured"
```

## Step 9: Verify Deployment

```bash
#!/usr/bin/env bash
# verify.sh

PROJECT_ID="my-project"
REGION="us-central1"
IG_NAME="github-runners-ig"

# List instances
gcloud compute instances list \
  --project=${PROJECT_ID} \
  --filter="labels.app:github-runner"

# Check startup script output
INSTANCE_NAME=$(gcloud compute instances list \
  --project=${PROJECT_ID} \
  --filter="labels.app:github-runner" \
  --format="value(name)" | head -1)

gcloud compute instances get-serial-port-output ${INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --zone=us-central1-a | tail -50

echo "✓ Deployment verified"
```

## Monitoring

### Check Runner Logs in Cloud Logging

```bash
gcloud logging read "resource.type=gce_instance AND jsonPayload.source=github-runner" \
  --project=${PROJECT_ID} \
  --limit=50 \
  --format=json
```

### SSH into Runner

```bash
gcloud compute ssh INSTANCE_NAME \
  --project=${PROJECT_ID} \
  --zone=us-central1-a
```

### Manual Health Check

```bash
# On runner instance
sudo bash /opt/runner-platform/scripts/health-check.sh
```

## Cost Optimization

- Use **Preemptible VMs** (70% cheaper, auto-restarts)
- Use **e2-standard-2** for most workloads
- Use **pd-standard** instead of pd-ssd for cost savings
- Schedule scale-down using Cloud Scheduler

## Cleanup

```bash
#!/usr/bin/env bash
# cleanup.sh

PROJECT_ID="my-project"
REGION="us-central1"
IG_NAME="github-runners-ig"
TEMPLATE_NAME="github-runner-template"
IMAGE_NAME="github-runner-image"

# Delete instance group
gcloud compute instance-groups managed delete ${IG_NAME} \
  --project=${PROJECT_ID} \
  --region=${REGION}

# Delete instance template
gcloud compute instance-templates delete ${TEMPLATE_NAME} \
  --project=${PROJECT_ID}

# Delete image
gcloud compute images delete ${IMAGE_NAME} \
  --project=${PROJECT_ID}

# Delete firewall rules
gcloud compute firewall-rules delete allow-github-api deny-all-egress \
  --project=${PROJECT_ID}

# Delete service account
gcloud iam service-accounts delete github-runner@${PROJECT_ID}.iam.gserviceaccount.com \
  --project=${PROJECT_ID}

echo "✓ All resources cleaned up"
```

## References

- [GCP Compute Engine Docs](https://cloud.google.com/compute/docs)
- [Managed Instance Groups](https://cloud.google.com/compute/docs/instance-groups)
- [Cloud Secret Manager](https://cloud.google.com/secret-manager)
- [Cloud Logging](https://cloud.google.com/logging/docs)
