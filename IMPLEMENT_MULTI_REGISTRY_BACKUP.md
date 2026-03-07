# Implementation Guide: Multi-Registry Backup Redundancy

**Status**: Ready to Implement  
**Effort**: 2-3 days  
**Priority**: 🔴 CRITICAL #1  
**Outcome**: 3-way backup distribution (Docker Hub → AWS ECR → Google Artifact Registry)

---

## Overview

This enhancement eliminates the Docker Hub single point of failure by automatically pushing backup images to 3 independent registries simultaneously. If Docker Hub becomes unavailable, recovery succeeds from AWS ECR or Google Artifact Registry.

---

## Prerequisites

1. AWS account with ECR access
   ```bash
   # Create ECR repository
   aws ecr create-repository --repository-name app-backup --region us-east-1
   ```

2. Google Cloud project with Artifact Registry
   ```bash
   # Create Artifact Registry repository
   gcloud artifacts repositories create docker-hub-mirror \
     --repository-format=docker \
     --location=us-east1 \
     --project=YOUR_PROJECT_ID
   ```

3. GitHub Actions secrets configured:
   - `AWS_ACCESS_KEY_ID` (IAM user with ECR push permissions)
   - `AWS_SECRET_ACCESS_KEY`
   - `GCP_PROJECT_ID`
   - `GCP_SERVICE_ACCOUNT_KEY` (JSON format)

---

## Step 1: Create Push Scripts

### scripts/push-to-aws-ecr.sh

```bash
#!/bin/bash
set -u

# Push Docker image to AWS ECR
# Usage: ./push-to-aws-ecr.sh <image-tag>

IMAGE_TAG="${1:?Image tag required}"
REGISTRY="123456789.dkr.ecr.us-east-1.amazonaws.com"
REPOSITORY="app-backup"

# AWS configuration from environment
: ${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID}
: ${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY}
: ${AWS_DEFAULT_REGION:=us-east-1}

log() {
  echo "[ECR] $(date +'%Y-%m-%d %H:%M:%S') $*"
}

log "Pushing to AWS ECR: $REGISTRY/$REPOSITORY:$IMAGE_TAG"

# Login to ECR
log "Logging in to AWS ECR..."
aws ecr get-login-password --region "$AWS_DEFAULT_REGION" | \
  docker login --username AWS --password-stdin "$REGISTRY" || {
  log "ERROR: ECR login failed"
  exit 1
}

# Tag image for ECR
log "Tagging image..."
docker tag "elevatediq/app-backup:$IMAGE_TAG" "$REGISTRY/$REPOSITORY:$IMAGE_TAG"
docker tag "elevatediq/app-backup:$IMAGE_TAG" "$REGISTRY/$REPOSITORY:latest"

# Push to ECR
log "Pushing image..."
docker push "$REGISTRY/$REPOSITORY:$IMAGE_TAG" || {
  log "ERROR: Push failed"
  exit 1
}

docker push "$REGISTRY/$REPOSITORY:latest" || {
  log "ERROR: Push of latest tag failed"
  exit 1
}

log "Successfully pushed to AWS ECR"

# Get image digest
DIGEST=$(docker inspect --format='{{.RepoDigests}}' \
  "$REGISTRY/$REPOSITORY:$IMAGE_TAG" | grep -oP 'sha256:[a-f0-9]{64}')

echo "aws_ecr_image=$REGISTRY/$REPOSITORY:$IMAGE_TAG"
echo "aws_ecr_digest=$DIGEST"
```

### scripts/push-to-gar.sh

```bash
#!/bin/bash
set -u

# Push Docker image to Google Artifact Registry
# Usage: ./push-to-gar.sh <image-tag>

IMAGE_TAG="${1:?Image tag required}"
LOCATION="us-east1"
REPOSITORY="docker-hub-mirror"
PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"

REGISTRY="$LOCATION-docker.pkg.dev/$PROJECT_ID/$REPOSITORY"

log() {
  echo "[GAR] $(date +'%Y-%m-%d %H:%M:%S') $*"
}

log "Pushing to Google Artifact Registry: $REGISTRY/app-backup:$IMAGE_TAG"

# Authenticate with GCP
log "Authenticating with Google Cloud..."
if [[ -n "${GCP_SERVICE_ACCOUNT_KEY:-}" ]]; then
  echo "$GCP_SERVICE_ACCOUNT_KEY" | docker login \
    -u _json_key \
    --password-stdin \
    "$LOCATION-docker.pkg.dev" || {
    log "ERROR: GCP authentication failed"
    exit 1
  }
else
  # Use gcloud configured credentials
  gcloud auth configure-docker "$LOCATION-docker.pkg.dev" || {
    log "ERROR: GCP authentication failed"
    exit 1
  }
fi

# Tag image for GAR
log "Tagging image..."
docker tag "elevatediq/app-backup:$IMAGE_TAG" "$REGISTRY/app-backup:$IMAGE_TAG"
docker tag "elevatediq/app-backup:$IMAGE_TAG" "$REGISTRY/app-backup:latest"

# Push to GAR
log "Pushing image..."
docker push "$REGISTRY/app-backup:$IMAGE_TAG" || {
  log "ERROR: Push failed"
  exit 1
}

docker push "$REGISTRY/app-backup:latest" || {
  log "ERROR: Push of latest tag failed"
  exit 1
}

log "Successfully pushed to Google Artifact Registry"

# Get image digest
DIGEST=$(docker inspect --format='{{.RepoDigests}}' \
  "$REGISTRY/app-backup:$IMAGE_TAG" | grep -oP 'sha256:[a-f0-9]{64}')

echo "gar_image=$REGISTRY/app-backup:$IMAGE_TAG"
echo "gar_digest=$DIGEST"
```

**Make executable**:
```bash
chmod +x scripts/push-to-aws-ecr.sh
chmod +x scripts/push-to-gar.sh
```

---

## Step 2: Create Multi-Registry Push Orchestration

### scripts/multi-registry-push.sh

```bash
#!/bin/bash
set -u

# Push backup image to all 3 registries in parallel
# Usage: ./multi-registry-push.sh <image-tag>

IMAGE_TAG="${1:?Image tag required}"

log() {
  echo "[ORCHESTRATOR] $(date +'%Y-%m-%d %H:%M:%S') $*"
}

log "Starting multi-registry push for $IMAGE_TAG"
log "Target registries: Docker Hub, AWS ECR, Google Artifact Registry"

# Create temp directory for outputs
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Track results
RESULTS_FILE="$TEMP_DIR/results.json"
cat > "$RESULTS_FILE" << 'EOF'
{
  "timestamp": "",
  "image_tag": "",
  "registries": {}
}
EOF

# Function to push to registry and capture result
push_to_registry() {
  local script=$1
  local registry_name=$2
  
  log "Starting push to $registry_name in background..."
  
  {
    if "$script" "$IMAGE_TAG" > "$TEMP_DIR/${registry_name}.log" 2>&1; then
      log "✓ $registry_name push succeeded"
      echo "{\"$registry_name\": {\"status\": \"success\"}}" > "$TEMP_DIR/${registry_name}.json"
    else
      log "✗ $registry_name push failed"
      cat "$TEMP_DIR/${registry_name}.log" | grep ERROR || true
      echo "{\"$registry_name\": {\"status\": \"failed\"}}" > "$TEMP_DIR/${registry_name}.json"
    fi
  } &
}

# Start pushes in parallel
push_to_registry "scripts/push-to-docker-hub.sh" "docker-hub" &
DOCKER_HUB_PID=$!

push_to_registry "scripts/push-to-aws-ecr.sh" "aws-ecr" &
AWS_ECR_PID=$!

push_to_registry "scripts/push-to-gar.sh" "google-artifact-registry" &
GAR_PID=$!

# Wait for all pushes to complete
log "Waiting for all registry pushes..."
wait

log "All pushes complete. Gathering results..."

# Collect results
docker_hub_status=$(jq -r '.["docker-hub"].status' "$TEMP_DIR/docker-hub.json" 2>/dev/null || echo "unknown")
aws_ecr_status=$(jq -r '.["aws-ecr"].status' "$TEMP_DIR/aws-ecr.json" 2>/dev/null || echo "unknown")
gar_status=$(jq -r '.["google-artifact-registry"].status' "$TEMP_DIR/google-artifact-registry.json" 2>/dev/null || echo "unknown")

# Generate summary
cat > multi-registry-push-results.json << EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "image_tag": "$IMAGE_TAG",
  "registries": {
    "docker-hub": {
      "status": "$docker_hub_status"
    },
    "aws-ecr": {
      "status": "$aws_ecr_status"
    },
    "google-artifact-registry": {
      "status": "$gar_status"
    }
  },
  "success_rate": "$(
    total=3
    success=0
    [[ "$docker_hub_status" == "success" ]] && ((success++))
    [[ "$aws_ecr_status" == "success" ]] && ((success++))
    [[ "$gar_status" == "success" ]] && ((success++))
    echo "$((success * 100 / total))%"
  )"
}
EOF

log "Multi-registry push complete"
log "Docker Hub: $docker_hub_status"
log "AWS ECR: $aws_ecr_status"
log "Google Artifact Registry: $gar_status"

# Print results
cat multi-registry-push-results.json | jq .

# Exit with error if all failed
if [[ "$docker_hub_status" == "failed" ]] && \
   [[ "$aws_ecr_status" == "failed" ]] && \
   [[ "$gar_status" == "failed" ]]; then
  log "ERROR: All registry pushes failed"
  exit 1
fi

# Exit with warning if some failed
if [[ "$docker_hub_status" == "failed" ]] || \
   [[ "$aws_ecr_status" == "failed" ]] || \
   [[ "$gar_status" == "failed" ]]; then
  log "WARNING: Some registries failed, but at least one succeeded"
  exit 0
fi

log "SUCCESS: All registries pushed successfully"
exit 0
```

**Make executable**:
```bash
chmod +x scripts/multi-registry-push.sh
```

---

## Step 3: Update GitHub Actions Workflow

Replace or enhance `.github/workflows/docker-hub-weekly-backup.yml`:

```yaml
name: Docker Hub Weekly Backup to Multi-Registry
on:
  schedule:
    - cron: '0 2 * * 1'  # Monday 2 AM UTC
  workflow_dispatch:

env:
  BACKUP_TAG: "backup-$(date +%Y%m%d-%H%M%S)"

jobs:
  backup-to-multi-registry:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKER_HUB_USERNAME }}
          password: ${{ secrets.DOCKER_HUB_PAT }}
      
      - name: Build backup image
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile.backup
          push: false
          load: true
          tags: |
            elevatediq/app-backup:${{ env.BACKUP_TAG }}
            elevatediq/app-backup:latest
          build-args: |
            BUILD_VERSION=1.0.0
            BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
            BUILD_COMMIT_SHA=${{ github.sha }}
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          credentials_json: ${{ secrets.GCP_SERVICE_ACCOUNT_KEY }}
      
      - name: Set GCP Project
        uses: google-github-actions/setup-gcloud@v2
        with:
          project_id: ${{ secrets.GCP_PROJECT_ID }}
      
      - name: Push to multi-registry (parallel)
        run: |
          bash scripts/multi-registry-push.sh "${{ env.BACKUP_TAG }}"
      
      - name: Verify all registries
        run: |
          echo "Docker Hub:"
          docker pull elevatediq/app-backup:${{ env.BACKUP_TAG }}
          
          echo "AWS ECR:"
          docker pull \
            123456789.dkr.ecr.us-east-1.amazonaws.com/app-backup:${{ env.BACKUP_TAG }}
          
          echo "Google Artifact Registry:"
          docker pull \
            us-east1-docker.pkg.dev/${{ secrets.GCP_PROJECT_ID }}/docker-hub-mirror/app-backup:${{ env.BACKUP_TAG }}
      
      - name: Store multi-registry results
        run: |
          git config user.email "github-actions@github.com"
          git config user.name "GitHub Actions"
          
          mkdir -p .backup-metadata
          cp multi-registry-push-results.json \
            .backup-metadata/latest-registry-push.json
          
          git add .backup-metadata/
          git commit -m "Multi-registry backup: ${{ env.BACKUP_TAG }}" || true
          git push || echo "Nothing to push"
      
      - name: Create release artifact
        run: |
          gh release create "backup-multi-registry-${{ env.BACKUP_TAG }}" \
            multi-registry-push-results.json \
            --title "Multi-Registry Backup ${{ env.BACKUP_TAG }}" \
            --notes "Backup pushed to Docker Hub, AWS ECR, and Google Artifact Registry"
```

---

## Step 4: Update Recovery Script

Enhance `scripts/recover-from-nuke.sh` to support multi-registry fallback:

```bash
# Add this function to recover-from-nuke.sh

BACKUP_REGISTRIES=(
  "docker.io"
  "123456789.dkr.ecr.us-east-1.amazonaws.com"
  "us-east1-docker.pkg.dev/$GCP_PROJECT_ID/docker-hub-mirror"
)

# Override old function if exists
attempt_pull_from_any_registry() {
  local image=$1
  local backup_tag=$2
  
  log "Attempting to pull backup image from available registries..."
  
  for registry in "${BACKUP_REGISTRIES[@]}"; do
    log "Trying: $registry/elevatediq/app-backup:$backup_tag"
    
    if docker pull "$registry/elevatediq/app-backup:$backup_tag"; then
      pass "Successfully pulled from $registry"
      
      # Re-tag for local use
      docker tag \
        "$registry/elevatediq/app-backup:$backup_tag" \
        "elevatediq/app-backup:latest"
      
      return 0
    else
      warn "Failed to pull from $registry, trying next..."
    fi
  done
  
  fail "All registry mirrors exhausted"
  return 1
}
```

---

## Step 5: Test the Implementation

### Local Testing

```bash
# Build test image
docker build -f Dockerfile.backup -t elevatediq/app-backup:test .

# Test pushing to each registry (requires credentials set)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export GCP_PROJECT_ID="..."
export GCP_SERVICE_ACCOUNT_KEY='...'

# Test individual pushes
./scripts/push-to-aws-ecr.sh test
./scripts/push-to-gar.sh test

# Test orchestration
./scripts/multi-registry-push.sh test
```

### Verify Results

```bash
# Check multi-registry results
cat multi-registry-push-results.json | jq .

# Pull from each registry to verify
docker pull docker.io/elevatediq/app-backup:test
docker pull 123456789.dkr.ecr.us-east-1.amazonaws.com/app-backup:test
docker pull us-east1-docker.pkg.dev/YOUR_PROJECT_ID/docker-hub-mirror/app-backup:test
```

---

## Step 6: Validation Checklist

- [ ] AWS ECR repository created
- [ ] Google Artifact Registry repository created  
- [ ] GitHub Actions secrets configured (5 total)
- [ ] `push-to-aws-ecr.sh` created and tested
- [ ] `push-to-gar.sh` created and tested
- [ ] `multi-registry-push.sh` created and tested
- [ ] Updated `.github/workflows/docker-hub-weekly-backup.yml`
- [ ] Enhanced `scripts/recover-from-nuke.sh` with fallback logic
- [ ] Can pull image from all 3 registries
- [ ] Workflow runs successfully on next Monday 2 AM UTC

---

## Cost Impact

| Registry | Monthly Cost | Storage | Bandwidth |
|----------|--------------|---------|-----------|
| Docker Hub | $0 | Free | $0 |
| AWS ECR | ~$0.31 | Included | ~$0.09 |
| Google Artifact Registry | ~$0.25 | ~50GB | ~$0.10 |
| **Total** | **~$0.65/month** | — | — |

---

## Rollback Plan

If issues occur:

```bash
# Temporarily disable AWS push
# In .github/workflows/docker-hub-weekly-backup.yml, comment out AWS ECR step

# Temporarily disable Google push  
# In .github/workflows/docker-hub-weekly-backup.yml, comment out GAR step

# Keep Docker Hub primary until issues resolved
```

---

## Success Criteria

✅ All done when:
1. Image successfully pushed to all 3 registries in parallel
2. Recovery script tries Docker Hub first, falls back to AWS ECR, then Google Artifact Registry
3. Weekly workflow completes in <10 minutes
4. `multi-registry-push-results.json` shows 100% success
5. All 3 registries remain in sync with same image digest

---

**Estimated Time**: 2-3 days  
**Next Step**: Implement Enhancement #2 (Cascading Fallback)
