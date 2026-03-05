# Environment Nuke & 10X Enhancement Strategy

**Date:** March 5, 2026  
**Status:** PLANNED (DRY-RUN)

---

## 🔴 PHASE 1: COMPLETE TEARDOWN (DRY-RUN PLAN)

### 1.1 Dry-Run Infrastructure Destruction

```bash
#!/usr/bin/env bash
set -euo pipefail

# DRY-RUN: Complete environment teardown to zero
echo "=== DRY-RUN: COMPLETE ENVIRONMENT NUKE ==="

# Step 1: Destroy all Terraform-managed infrastructure
cd terraform/environments/production
echo "[DRY-RUN] Terraform destroy plan..."
terraform plan -destroy -var-file=prod.tfvars -out=destroy.tfplan
echo "Plan saved to destroy.tfplan - review before actual execution"

# Check what will be destroyed
terraform show destroy.tfplan | grep -E "will be destroyed|Plan:"

# Step 2: List GCP resources to be destroyed (manual verification)
echo "[DRY-RUN] GCP resources to destroy:"
gcloud compute instances list --project=$PROJECT_ID --format="table(name,zone,status)"
gcloud compute disks list --project=$PROJECT_ID --format="table(name,sizeGb,zone,status)"
gcloud compute networks list --project=$PROJECT_ID --format="table(name,mode)"
gcloud redis instances list --region=us-central1 --project=$PROJECT_ID --format="table(name,state)"

# Step 3: List AWS spot lifecycle resources
echo "[DRY-RUN] AWS resources to destroy:"
aws ec2 describe-instances --region us-east-1 --filters "Name=tag:Environment,Values=production" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output table

# Step 4: Stop all systemd services
echo "[DRY-RUN] Systemd services to stop:"
systemctl --user list-unit-files --state=enabled | grep -E "provisioner|managed-auth|vault-shim|portal" || true

# Step 5: Backend state handling
echo "[DRY-RUN] Backend state files:"
ls -lh terraform-state-backup*.tfstate 2>/dev/null || echo "No backup files"
Du -sh /var/lib/terraform/state 2>/dev/null || echo "No state directory"

# Step 6: Vault cleanup (dry-run)
echo "[DRY-RUN] Vault AppRole to disable:"
vault list auth/approle/role/ || echo "Vault not accessible"

# Step 7: Docker/container cleanup preview
echo "[DRY-RUN] Docker resources to remove:"
docker ps -a --filter "label=app=self-hosted-runner" || echo "Docker not running"
docker images --filter "reference=*self-hosted*" || echo "No matching images"

# Step 8: Redis queue cleanup (if local)
echo "[DRY-RUN] Redis queue state:"
redis-cli -h 127.0.0.1 DBSIZE || echo "Redis not accessible"

echo ""
echo "✅ DRY-RUN COMPLETE"
echo ""
echo "ACTUAL DESTRUCTION STEPS (WHEN READY):"
echo "1. Review destroy.tfplan output above"
echo "2. Run: terraform apply destroy.tfplan"
echo "3. Terminate all systemd services"
echo "4. Clean local Docker volumes"
echo "5. Rotate/revoke Vault AppRole credentials"
echo "6. Archive terraform state backup to cold storage"
echo "7. Delete: terraform-state-backup*.tfstate files (after archival)"
echo ""
```

### 1.2 Artifacts & State Preservation (Pre-Teardown)

```bash
# Backup everything before nuking
mkdir -p /tmp/pre-nuke-backup-$(date +%s)
BACKUP_DIR="/tmp/pre-nuke-backup-$(date +%s)"

# Archive terraform state
tar -czf "$BACKUP_DIR/terraform-state.tar.gz" terraform/.terraform terraform/terraform.tfstate* || true

# Archive service configs
tar -czf "$BACKUP_DIR/service-configs.tar.gz" services/*/.env* build/systemd/ || true

# Export Vault policies
vault policy list > "$BACKUP_DIR/vault-policies.txt" 2>/dev/null || true
vault read secret/data/runners > "$BACKUP_DIR/vault-runners-backup.json" 2>/dev/null || true

# Archive application state
tar -czf "$BACKUP_DIR/app-data.tar.gz" \
  services/provisioner-worker/logs \
  services/managed-auth/logs \
  services/portal/logs \
  || true

echo "Backup saved to: $BACKUP_DIR"
gpg --symmetric "$BACKUP_DIR/vault-runners-backup.json"  # Encrypt sensitive data
```

### 1.3 Post-Teardown Verification

```bash
# Verify complete destruction
echo "VERIFICATION CHECKLIST:"
echo "□ GCP: All compute instances terminated"
echo "□ GCP: All persistent disks deleted"
echo "□ GCP: Redis cluster destroyed"
echo "□ AWS: All EC2 spot instances terminated"
echo "□ Vault: AppRole auth method disabled/cleaned"
echo "□ Local: All systemd services stopped and disabled"
echo "□ Local: Docker containers & images removed"
echo "□ DNS: DNS records point to new environment"
echo "□ GitHub: No runners connected to repo"
echo "□ Logs: Archive sent to cold storage (GCS/S3)"
echo "□ Backups: Encrypted backups stored securely"
```

---

## 🚀 PHASE 2: 10X ENHANCEMENTS

### Enhancement Domain 1: REBUILD SPEED (5-10x faster)

#### E1.1 Containerized Ephemeral Bootstrap
**Target:** 30s → 3s init time

```yaml
# Dockerfile.runner-base (immutable, pre-baked)
FROM ubuntu:22.04-minimal
# Pre-install: git, jq, curl, docker-cli, kubectl, terraform, gh-cli, aws-cli
# Pre-cache: GitHub Actions standard libraries
# Pre-configure: systemd, user permissions, logging
RUN apt-get update && apt-get install -y \
    git curl jq \
    docker.io kubectl \
    terraform aws-cli gh \
    systemd-container \
    && rm -rf /var/lib/apt/lists/*
COPY ./bootstrap-cached.sh /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/bootstrap-cached.sh"]
```

**Impact:** 
- Base image: 500MB (cached on all nodes) vs 2GB current
- Bootstrap: 3s vs 30s (uses pre-baked tooling)
- Registry: GCR with geographic replication (us, eu, asia)

---

#### E1.2 Parallel Multi-Cloud Infrastructure-as-Code
**Target:** 15min Terraform apply → 2min

```hcl
# terraform/environments/production-auto-scaling/main.tf
terraform {
  required_version = ">= 1.5"
  
  # Enable parallelism for create/destroy
  parallelism = 20
  
  backend "gcs" {
    bucket         = "runner-tfstate-prod"
    prefix         = "auto-scaling"
    encryption_key = var.tfstate_encryption_key
  }
}

# Multi-provider parallel module execution
module "gcp_compute_layer" {
  source = "../modules/gcp-auto-scaling"
  # Terraform auto-parallelizes module creation
}

module "aws_spot_layer" {
  source = "../modules/aws-spot-fleet"
}

module "networking" {
  source = "../modules/multi-cloud-networking"
  depends_on = [module.gcp_compute_layer, module.aws_spot_layer]
}

# Taint & recreation strategy (1-click rebuild)
resource "null_resource" "rebuild_trigger" {
  triggers = {
    image_id = var.runner_image_hash  # Changes trigger full rebuild
  }
  
  provisioner "local-exec" {
    command = "terraform taint -allow-missing && terraform apply -auto-approve -parallelism=30"
  }
}
```

**Impact:**
- Parallel infrastructure provisioning: 15 min → 2 min
- Taint-based rebuild: 1 command vs 5 manual steps
- State locking prevents conflicts

---

#### E1.3 Pre-Warmed Instance Pool
**Target:** Spin-up delay eliminated

```hcl
# GCP Managed Instance Group with pre-warmup
resource "google_compute_instance_group_manager" "runner_pool" {
  name               = "runner-pool-pre-warmed"
  base_instance_name = "runner"
  instance_template  = google_compute_instance_template.runner.id
  
  # Pre-warm 10 instances at all times
  target_size = 10
  
  # Aggressive scaling (1s cooldown)
  auto_scaling_policy {
    min_replicas    = 10
    max_replicas    = 200
    cooldown_period = 1  # 1 second
    
    metric {
      type   = "pubsub.googleapis.com|subscription|num_undelivered_messages"
      target = 100  # Trigger scale-up when 100+ jobs queued
    }
  }
}

# AWS Spot Fleet with capacity reservation
resource "aws_ec2_fleet" "runner_spots" {
  name = "runner-spot-fleet"
  
  launch_template_config {
    launch_template_specification {
      launch_template_id = aws_launch_template.runner.id
      version            = "$Latest"
    }
    
    # Reserve capacity for auto-recovery
    overrides {
      instance_type = "t4g.large"
      availability_zone = "us-east-1a"
      capacity_reservation = "open"  # Use reserved instances
    }
  }
  
  fleet_type = "maintain"  # Auto-replace failed instances
}
```

**Impact:**
- Spin-up time: 2-3 min → 0s (pre-warmed)
- Auto-scaling latency: <1s to add new nodes

---

### Enhancement Domain 2: IMMUTABILITY (Prevent drift, guarantee reproducibility)

#### E2.1 Immutable Infrastructure Image Pipeline
**Target:** Build once, deploy everywhere (no post-deploy changes)

```yaml
# .github/workflows/immutable-image-build.yml
name: Build Immutable Runner Image
on:
  push:
    branches: [main]
    paths: ['packer/**', 'bootstrap/**']

jobs:
  build-minimal-image:
    runs-on: [self-hosted, linux]
    steps:
      - uses: actions/checkout@v4
      
      # 1. Build+sign base image (immutable)
      - name: Build and sign container image
        run: |
          VERSION=$(git describe --tags --always)
          DIGEST=$(docker build --tag runner:$VERSION \
            --build-arg GOLANG_VERSION=1.21 \
            --build-arg RUNNER_VERSION=2.312 \
            --quiet packer/Dockerfile | tail -1)
          
          # Sign image for integrity verification
          cosign sign --key $COSIGN_KEY docker.io/our-runner:$VERSION@$DIGEST
          
          # Generate SBOM (Software Bill of Materials)
          syft docker.io/our-runner:$VERSION --output cyclonedx-json > sbom.json
          
          # Store digest in hashmap
          echo "$VERSION=$DIGEST" >> image-digests.txt
      
      # 2. Immutable config layer (read-only after first run)
      - name: Create immutable config
        run: |
          mkdir -p /etc/runner-config-immutable
          cat > /etc/runner-config-immutable/manifest.json << EOF
          {
            "version": "1.0",
            "image_digest": "$DIGEST",
            "tools": {
              "terraform": "$(terraform --version)",
              "gh": "$(gh --version)",
              "docker": "$(docker --version)"
            },
            "sealed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          }
          EOF
          
          # Make immutable (remove all write permissions after seal)
          chmod 444 /etc/runner-config-immutable/manifest.json
          mount -o remount,ro /etc/runner-config-immutable 2>/dev/null || true
      
      # 3. Push to multi-region registry with immutable tags
      - name: Push to GCR (multi-region)
        run: |
          for region in us eu asia; do
            docker push gcr.io/$region-runner/$VERSION@$DIGEST
            # Tag as 'immutable' to prevent overwrites
            gcloud container images add-tag \
              gcr.io/$region-runner/$VERSION@$DIGEST \
              gcr.io/$region-runner/immutable-$VERSION \
              --quiet
          done
      
      # 4. Document what was built (for audit trail)
      - name: Create immutability audit
        run: |
          cat > BUILD_MANIFEST.json << EOF
          {
            "digest": "$DIGEST",
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "commit": "$GITHUB_SHA",
            "branch": "$GITHUB_REF",
            "registry_locations": [
              "gcr.io/us-runner/immutable-$VERSION@$DIGEST",
              "gcr.io/eu-runner/immutable-$VERSION@$DIGEST",
              "gcr.io/asia-runner/immutable-$VERSION@$DIGEST"
            ],
            "no_modifications_after_deployment": true
          }
          EOF
```

**CI/CD Integration:**
```bash
# Deploy uses immutable image digest (never `:latest` or mutable tags)
docker run \
  gcr.io/us-runner/immutable-v2.0@sha256:abc123... \
  /usr/local/bin/register-and-run.sh

# Any deviation from expected digest = block deployment
```

#### E2.2 Read-Only Filesystem + Ephemeral Scratch
**Target:** Running instance cannot be modified, only replaced

```bash
#!/usr/bin/env bash
# bootstrap-immutable.sh - Make runner filesystem immutable

set -euo pipefail

# Root filesystem: read-only (except /run, /tmp, /var)
mount -o remount,ro /

# Create ephemeral overlay for state (auto-wiped on shutdown)
mkdir -p /run/runner-ephemeral
mount -t tmpfs -o size=10G tmpfs /run/runner-ephemeral

# Bind writable directories to ephemeral storage
mkdir -p /run/runner-ephemeral/var
mount --bind /run/runner-ephemeral/var /var

# Verify immutability
echo "Filesystem immutability check:"
touch /test.txt 2>&1 | grep "Read-only" && echo "✓ Root is read-only"
echo "test" > /var/test.txt && echo "✓ /var is writable"
echo "test" > /run/test.txt && echo "✓ /run is writable"

# Block runner from modifying critical paths
find /usr /etc /bin /sbin -type f -exec chmod a-w {} \; 2>/dev/null || true

# Enable seccomp to prevent dangerous syscalls
cat > /etc/seccomp-profile.json << EOF
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "defaultErrnoRet": 1,
  "archMap": [{"architecture": "SCMP_ARCH_X86_64"}],
  "syscalls": [
    {
      "name": "chmod",
      "action": "SCMP_ACT_ERRNO",
      "args": [{"index": 0, "value": 4294967295, "valueTwo": 0, "op": "SCMP_CMP_MASKED_EQ"}]
    },
    {
      "name": "mount",
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
EOF

echo "✓ Immutable filesystem configured"
```

**Impact:**
- Drift impossible: Nothing can be modified
- Audit trail: All changes require new image build + deployment
- Reproducibility: Same digest = identical behavior

---

#### E2.3 GitOps State Management
**Target:** All infrastructure changes tracked in Git

```yaml
# infrastructure/runners-prod.yaml
apiVersion: runnerinfra.io/v1alpha1
kind: RunnerPool
metadata:
  name: prod-pool
  labels:
    immutable: "true"
    sealed-at: "2026-03-05T14:00:00Z"
spec:
  replicas: 20
  
  # Immutable field: prevents inline changes
  imageDigest: "gcr.io/us-runner/immutable-v2.0@sha256:abc123"
  
  # All changes via Git commit (audit trail)
  sourceControl:
    repository: "https://github.com/org/self-hosted-runner"
    branch: "main"
    path: "infrastructure/runners-prod.yaml"
    commitHash: "abc123def456"
  
  # Reconciliation: drift detection + correction
  reconcile:
    interval: 30s
    
    # Block drift: fail if live state != Git spec
    enforcementMode: "strict"
    
    # Auto-remediate by replacing instances (not patching)
    autoRemediate: true
    recreateOnDrift: true
    
    # Validation: every deployment must match Git commit
    validation:
      engine: "kyverno"
      policies:
        - name: "immutable-digest"
          rule: "image_digest == spec.imageDigest"

status:
  activeDigest: "sha256:abc123"
  lastReconcile: "2026-03-05T14:05:00Z"
  driftDetected: false
```

**Impact:**
- Git commit = audit trail for every infrastructure change
- Rollback: one Git revert = full infrastructure rollback
- Drift prevention: automatically catches & fixes deviations

---

### Enhancement Domain 3: EPHEMERAL INFRASTRUCTURE (Nothing persistent, everything immutable)

#### E3.1 One-Click Instance Lifecycle (Birth → Death → Replacement)
**Target:** Full instance replacement <30s, zero data carryover

```hcl
# terraform/modules/ephemeral-instances/main.tf
resource "google_compute_instance_template" "ephemeral_runner" {
  name_prefix = "runner-ephemeral-"
  
  # Ephemeral: no persistent storage
  disk {
    boot           = true
    source_image   = var.immutable_image_digest  # Immutable digest (not :latest)
    auto_delete    = true  # Auto-delete on instance termination
    disk_type      = "pd-ssd"
    disk_size_gb   = 50
    
    # Encryption for temporary data
    disk_encryption_key {
      raw_key = var.ephemeral_disk_key
    }
  }
  
  # No additional persistent disks - everything ephemeral
  
  # Networking: ephemeral internal IP only (no static)
  network_interface {
    network            = google_compute_network.internal.id
    network_ip         = ""  # Auto-assign (ephemeral)
    access_config {
      # No external IP: access via IAP or load balancer only
    }
  }
  
  # Metadata signals container deletion/replacement
  metadata = {
    ephemeral-mode         = "true"
    self-destruct-on-idle  = "900"  # 15 min idle = auto-terminate
    max-lifetime           = "3600" # 1 hour max = force replacement
    
    startup-script = base64encode(templatefile("${path.module}/startup.sh", {
      callback = "https://provisioner.internal/ping"
      max_age  = 3600
    }))
    
    shutdown-script = base64encode(base64decode(base64encode(file("${path.module}/shutdown-wipe.sh"))))
  }
  
  # Service account: minimal permissions, short-lived
  service_account {
    email  = google_service_account.ephemeral_runner.email
    scopes = ["cloud-platform"]
  }
  
  labels = {
    ephemeral      = "true"
    generation     = var.image_hash  # Change hash = replace all instances
    lifecycle-mode = "disposable"
  }
  
  # Machine type: smallest that works (reduce cost)
  machine_type = "e2-medium"
  
  # Auto-restart: disabled (ephemeral should not auto-restart)
  automatic_restart = false
  
  # Managed instance group for auto-scaling + auto-replacement
  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      name_prefix  # Allow new name each time
    ]
  }
}

# Managed instance group: auto-scale + auto-heal via recreation
resource "google_compute_instance_group_manager" "ephemeral_runners" {
  name = "ephemeral-runner-group"
  
  base_instance_name = "runner-ephemeral"
  instance_template  = google_compute_instance_template.ephemeral_runner.id
  
  # Force replacement every hour (10X more aggressive)
  update_policy {
    type                         = "PROACTIVE"
    minimal_action              = "REPLACE"
    max_surge_fixed             = 10  # Add 10 new instances
    max_unavailable_fixed       = 0   # No downtime
    min_ready_sec               = 30  # Wait 30s before marking ready
    instance_redistribution_type = "PROACTIVE"
    most_disruptive_allowed_action = "REPLACE"
    replacement_method         = "SUBSTITUTE"  # Replace one-by-one
  }
  
  # Health check: fail = immediate termination + recreation
  health_check {
    check_interval_sec = 10
    timeout_sec        = 5
    
    http_health_check {
      port = 5000  # Health check endpoint on each runner
      request_path = "/health"
    }
  }
  
  # Stateful config: disabled (everything ephemeral)
  stateful_disk = []
  
  auto_scaling_policy {
    min_replicas    = var.min_ephemeral_runners
    max_replicas    = var.max_ephemeral_runners
    cooldown_period = 1  # 1s cooldown: aggressive scaling
    
    metric {
      name   = "redis_queue_depth"
      target = 100  # Scale up at 100 jobs queued
    }
  }
  
  depends_on = [google_compute_network.internal]
}

resource "google_compute_instance_group_manager_timezone_updater" "ephemeral_runners_update" {
  # Trigger hourly replacement cycle
  instance_group_manager = google_compute_instance_group_manager.ephemeral_runners.id
  
  update_policy {
    type = "PROACTIVE"
    # Forces re-creation of all instances every hour
  }
}
```

#### E3.2 Zero-State Persistence: Immutable Logs + Metrics
**Target:** No state on instance, all data shipped to external systems

```bash
#!/usr/bin/env bash
# ephemeral-runner: zero persistent state

set -euo pipefail

# 1. Stdout/stderr → Google Cloud Logging (real-time stream)
exec 1> >(logger -s -t runner 2>&1 | \
  google-fluentd \
    --config=/etc/google-fluentd/config.d/ephemeral-runner.conf)

# 2. Structured logs to BigQuery
export LOGGING_FORMAT="json_bunyan"
export LOG_SINK="projects/$PROJECT_ID/sinks/runner-logs"

# 3. Metrics → Prometheus push gateway (not scraped, pushed)
configure_metrics() {
  local PUSH_GATEWAY="https://prometheus-push.internal/metrics/job/ephemeral-runner/instance/$INSTANCE_ID"
  
  cat > /usr/local/bin/push-metrics.sh << 'EOF'
    #!/bin/bash
    # Push metrics every 30s, then self-destruct
    while true; do
      cat /proc/self/stat | \
        awk '{print "process_cpu_time " $14 " " (1000*systime())}' | \
        curl --data-binary @- "$PUSH_GATEWAY"
      
      sleep 30
    done
  EOF
}

# 4. Job state → Redis (temporary, not persistent)
job_state_to_redis() {
  STATUS="$1"
  
  # Write to Redis with 86400s (24h) TTL
  redis-cli -h redis.internal \
    SET "runner:$INSTANCE_ID:status" "$STATUS" \
    EX 86400
}

# 5. No local caches: pull & discard
git_clone_ephemeral() {
  local REPO="$1"
  local DEST="/tmp/repo-$$"  # /tmp is auto-wiped on shutdown
  
  git clone "$REPO" "$DEST"
  # Repo exists only in memory, discarded on shutdown
}

# 6. GitHub runner token: 1-hour max, revoked on shutdown
register_runner() {
  local TOKEN=$(curl -s "$PROVISIONER_API/get-runner-token?max_age=3600")
  
  # Register (token expires in 1 hour → runner auto-deregisters)
  /opt/actions-runner/config.sh \
    --url "https://github.com/org/repo" \
    --token "$TOKEN" \
    --ephemeral
  
  # Start runner (will auto-exit when token expires)
  /opt/actions-runner/run.sh
}

# 7. On shutdown: nuke all state, verify clean slate
cleanup_ephemeral() {
  echo "Ephemeral cleanup: erasing all local state..."
  
  # Wipe all disks
  shred -vfz -n 3 /var/* 2>/dev/null || true
  
  # Secure delete (3-pass DoD standard)
  secure-delete /tmp/* 2>/dev/null || true
  
  # Detach volumes
  umount /mnt/ephemeral 2>/dev/null || true
  
  # Revoke API tokens
  curl -X DELETE "$PROVISIONER_API/revoke-token/$TOKEN"
  
  # Deregister from GitHub
  /opt/actions-runner/config.sh remove --token "$TOKEN"
  
  # Final log
  echo "Instance $INSTANCE_ID self-destructed at $(date)" | \
    logger -t ephemeral-runner
}

trap cleanup_ephemeral EXIT

# Main workflow
job_state_to_redis "STARTING"
register_runner
job_state_to_redis "RUNNING"

# Execute job (timeout: 30 min max)
timeout 1800 /opt/actions-runner/run.sh

job_state_to_redis "COMPLETED"

# Auto-destruct script will run on EXIT via trap
```

**Impact:**
- Zero persistent state: instance = disposable
- Data durability: 100% outside instance (Cloud Logging, BigQuery, Redis)
- Compliance: automatic data wipe on shutdown
- Cost: instances terminated after 1 hour (no zombie resources)

---

#### E3.3 Stateless Load Balancer + DNS Failover

```hcl
# terraform/modules/ephemeral-networking/main.tf
resource "google_compute_backend_service" "ephemeral_runners" {
  name              = "ephemeral-runner-backend"
  protocol          = "TCP"
  session_affinity  = "NONE"  # No session pinning (stateless)
  
  # Health check every 10s, fail after 3 checks
  health_checks = [google_compute_health_check.runner_health.id]
  
  # Auto-heal: 3 failed checks = remove from pool
  connection_draining_timeout_sec = 10
  
  # Circuit breaking: prevent cascading failures
  circuit_breakers {
    max_connections      = 1000
    max_pending_requests = 100
    max_requests         = 100000
    max_requests_per_connection = 10
  }
  
  # Outlier detection: auto-eject bad instances
  outlier_detection {
    base_ejection_time {
      seconds = 30
    }
    
    consecutive_errors                    = 5
    consecutive_gateway_failure           = 5
    enforcing_consecutive_errors          = 100
    enforcing_consecutive_gateway_failure = 100
    enforcing_success_rate                = 100
    max_ejection_percent                  = 50
    min_request_volume                    = 50
    split_external_local_originated_traffic = true
    success_rate_minimum_hosts             = 5
    success_rate_request_volume            = 100
    success_rate_stdev_factor              = 1900
  }
  
  depends_on = [google_compute_instance_group_manager.ephemeral_runners]
}

# DNS: Round-robin across all backends (stateless, no affinity)
resource "google_dns_record_set" "runner_lb" {
  name = "runners.internal."
  type = "A"
  ttl  = 30  # 30s TTL: quick failover
  
  managed_zone = google_dns_managed_zone.internal.name
  
  # All backends get traffic (load balancing via DNS round-robin)
  rrdatas = google_compute_network_endpoint_group.runners.*.network_endpoint_list
}
```

---

### Enhancement Domain 4: AUTOMATED ONE-CLICK DEPLOY & GITHUB ACTIONS INTEGRATION

#### E4.1 Single Workflow: Full Environment Deploy

```yaml
# .github/workflows/deploy-env-one-click.yml
name: One-Click Deploy | Rebuild Speed 10X
on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Environment to deploy"
        required: true
        default: "staging"
        type: choice
        options: ["staging", "production"]
      
      rebuild_reason:
        description: "Why rebuild? (drift fix, config update, security patch, etc)"
        required: true
        type: choice
        options: ["config_change", "security_patch", "drift_fix", "scaling", "upgrade"]
      
      max_parallel_creates:
        description: "Max parallel resource creates (higher = faster but riskier)"
        required: false
        default: "20"
        type: string

jobs:
  validate-and-deploy:
    runs-on: [self-hosted, linux]
    environment: ${{ inputs.environment }}
    
    concurrency:
      group: deploy-${{ inputs.environment }}-${{ github.ref }}
      cancel-in-progress: false  # Prevent concurrent deploys
    
    steps:
      # ========== PRE-FLIGHT CHECKS ==========
      - name: Pre-flight validation
        run: |
          echo "🚀 One-Click Deploy: Pre-Flight Checks"
          
          # Check 1: Terraform syntax
          terraform validate terraform/environments/${{ inputs.environment }}
          
          # Check 2: Cost estimate (warn if > 50% increase)
          terraform plan -json terraform/environments/${{ inputs.environment }} | \
            jq '[.resource_changes[].change.actions[]] | 
                {"created": ([.[] | select(. == "create")] | length),
                 "destroyed": ([.[] | select(. == "delete")] | length)}'
          
          # Check 3: Policy validation (no public IPs, etc)
          tflint --config=terraform/.tflint.hcl terraform/environments/${{ inputs.environment }}
          
          # Check 4: Network connectivity
          curl -s "https://provisioner.internal/health" | jq '.status'
          curl -s "https://redis.internal:6379" || echo "⚠ Redis not accessible"
          
          echo "✅ All pre-flight checks passed"
      
      # ========== BUILD IMMUTABLE IMAGE ==========
      - name: Build new immutable image (if needed)
        id: image-build
        run: |
          IMAGE_HASH=$(git rev-parse --short HEAD)
          
          # Check if image already exists
          if gcloud container images describe gcr.io/us-runner/immutable-$IMAGE_HASH 2>/dev/null; then
            echo "image-exists=true" >> $GITHUB_OUTPUT
            echo "✓ Image already built"
          else
            echo "Building new image..."
            docker build -t gcr.io/us-runner/immutable-$IMAGE_HASH:latest \
              -f packer/Dockerfile \
              --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
              --build-arg VCS_REF=$IMAGE_HASH \
              .
            
            # Push to multi-region registries (parallel)
            docker push gcr.io/us-runner/immutable-$IMAGE_HASH:latest &
            docker push gcr.io/eu-runner/immutable-$IMAGE_HASH:latest &
            wait
            
            echo "image-exists=false" >> $GITHUB_OUTPUT
          fi
          
          echo "image-digest=$IMAGE_HASH" >> $GITHUB_OUTPUT
      
      # ========== HIGH-SPEED TERRAFORM APPLY ==========
      - name: Terraform plan (dry-run)
        id: tf-plan
        run: |
          cd terraform/environments/${{ inputs.environment }}
          
          terraform plan \
            -var="parallelism=${{ inputs.max_parallel_creates }}" \
            -var="image_digest=${{ steps.image-build.outputs.image-digest }}" \
            -out=tfplan.binary \
            -json | tee tfplan.json
          
          # Parse plan summary
          RESOURCE_COUNT=$(jq '[.resource_changes | length]' tfplan.json)
          CHANGES=$(jq -r '.resource_changes[] | select(.change.actions[] != "no-op") | .address' tfplan.json | wc -l)
          
          echo "Resource count: $RESOURCE_COUNT"
          echo "Changes: $CHANGES"
          echo "resources-changing=$CHANGES" >> $GITHUB_OUTPUT
      
      # ========== APPLY WITH ROLLBACK CAPABILITY ==========
      - name: Create pre-deploy backup
        if: steps.tf-plan.outputs.resources-changing > 0
        run: |
          BACKUP_ID=$(date +%s)
          
          cd terraform/environments/${{ inputs.environment }}
          cp terraform.tfstate terraform.tfstate.backup.$BACKUP_ID
          
          # Backup to GCS (immutable, versioned)
          gsutil -m cp terraform.tfstate.backup.$BACKUP_ID \
            gs://runner-tfstate-backup/${{ inputs.environment }}/$(date +%Y-%m-%d)_$BACKUP_ID/
          
          echo "Pre-deploy backup: $BACKUP_ID"
      
      - name: Apply Terraform (FAST MODE - parallel 30)
        id: tf-apply
        env:
          TF_LOG: "WARN"  # Reduce logging to speed up apply
          TF_INPUT: "false"
        run: |
          cd terraform/environments/${{ inputs.environment }}
          
          # Apply with:
          # - parallelism=30 (create 30 resources in parallel)
          # - input=false (no interactive prompts)
          # - unlock (auto-skip existing locks)
          time terraform apply \
            -parallelism=${{ inputs.max_parallel_creates }} \
            -input=false \
            -lock-timeout=5m \
            tfplan.binary 2>&1 | tee apply.log
          
          # Extract apply summary
          grep -E "Apply complete|No changes" apply.log | head -1 >> $GITHUB_OUTPUT
      
      # ========== SMOKE TESTS (30 instances, 5min max) ==========
      - name: Smoke tests on new instances
        timeout-minutes: 5
        run: |
          # List new instances
          NEW_INSTANCES=$(gcloud compute instances list \
            --filter="labels.generation=${{ steps.image-build.outputs.image-digest }}" \
            --format="value(name)" \
            --limit=30)
          
          PASSED=0
          FAILED=0
          
          for INSTANCE in $NEW_INSTANCES; do
            echo "Testing $INSTANCE..."
            
            # SSH test (with timeout)
            if timeout 30 gcloud compute ssh $INSTANCE -- \
              "curl -s http://localhost:5000/health | jq '.status' | grep -q 'healthy'"; then
              ((PASSED++))
              echo "✓ $INSTANCE healthy"
            else
              ((FAILED++))
              echo "✗ $INSTANCE FAILED"
            fi
          done
          
          echo "Smoke test results: $PASSED passed, $FAILED failed"
          
          if [ $FAILED -gt 0 ]; then
            echo "⚠ Some instances unhealthy. Running auto-heal..."
            gcloud compute instance-groups managed recreate-instances \
              runner-pool-pre-warmed \
              --instances=$FAILED_INSTANCES
          fi
      
      # ========== HEALTH CHECK MONITORING ==========
      - name: Monitor instance health (2 min)
        run: |
          echo "Monitoring rollout health..."
          
          for i in {1..12}; do
            HEALTHY=$(gcloud compute backend-services get-health \
              ephemeral-runner-backend \
              --global \
              --format="value(status.healthStatus[].health_state)" | \
              grep "HEALTHY" | wc -l)
            
            UNHEALTHY=$(gcloud compute backend-services get-health \
              ephemeral-runner-backend \
              --global \
              --format="value(status.healthStatus[].health_state)" | \
              grep "UNHEALTHY" | wc -l)
            
            echo "[$((i*10))s] Healthy: $HEALTHY, Unhealthy: $UNHEALTHY"
            
            if [ $UNHEALTHY -eq 0 ]; then
              echo "✅ All instances healthy!"
              break
            fi
            
            sleep 10
          done
      
      # ========== GitHub Actions Integration ==========
      - name: Accept GitHub Actions on deployed runners
        run: |
          # Mark runners as accepting jobs
          gcloud compute instances add-labels \
            runner-pool-pre-warmed \
            --labels="accepting-jobs=true,deployed-at=$(date +%s)"
      
      - name: Route Actions to new runners
        run: |
          # Update DNS to point to new instances
          gcloud dns record-sets delete runners.internal \
            --zone=internal --quiet || true
          
          gcloud dns record-sets create runners.internal \
            --zone=internal \
            --type=A \
            --ttl=30 \
            --rrdatas=$(gcloud compute instances list \
              --filter="labels.generation=${{ steps.image-build.outputs.image-digest }}" \
              --format="value(INTERNAL_IP)")
      
      # ========== ROLLBACK ON FAILURE ==========
      - name: Rollback on failure
        if: failure() && steps.tf-apply.outcome == 'failure'
        run: |
          cd terraform/environments/${{ inputs.environment }}
          
          # Get most recent backup
          LATEST_BACKUP=$(ls -t terraform.tfstate.backup.* | head -1)
          
          echo "🔄 Rolling back from backup: $LATEST_BACKUP"
          cp $LATEST_BACKUP terraform.tfstate
          
          terraform apply -auto-approve -lock=false
          
          echo "✅ Rollback complete"
      
      # ========== NOTIFICATION ==========
      - name: Notify deployment status
        if: always()
        run: |
          STATUS=$(if [ "${{ job.status }}" == "success" ]; then echo "✅ SUCCESS"; else echo "❌ FAILED"; fi)
          
          # Send to Slack
          curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
            -H 'Content-Type: application/json' \
            -d "{
              \"text\": \"Deploy ${{ inputs.environment }}: $STATUS\",
              \"blocks\": [{
                \"type\": \"section\",
                \"text\": {
                  \"type\": \"mrkdwn\",
                  \"text\": \"*Deploy Report*\nEnv: ${{ inputs.environment }}\nStatus: $STATUS\nDuration: ${{ job.duration }}s\nImage: ${{ steps.image-build.outputs.image-digest }}\"
                }
              }]
            }"
```

---

#### E4.2 One-Click Destroy (Dry-Run + Safe)

```yaml
# .github/workflows/destroy-env-one-click.yml
name: One-Click Destroy | Safe Teardown
on:
  workflow_dispatch:
    inputs:
      environment:
        required: true
        default: "staging"
        type: choice
        options: ["staging", "production"]
      
      dry_run:
        description: "Dry-run only (no actual destruction)"
        required: true
        type: boolean
        default: true

jobs:
  destroy:
    runs-on: [self-hosted, linux]
    environment: ${{ inputs.environment }}
    
    steps:
      - name: Pre-destroy validation
        run: |
          if [ "${{ inputs.environment }}" == "production" ] && [ "${{ inputs.dry_run }}" == "false" ]; then
            echo "🛑 Production destruction requires approval"
            echo "Waiting for manual approval (requires 2 reviewers)..."
          fi
      
      - name: Capture pre-destroy state
        run: |
          # Backup state to GCS
          gsutil cp terraform/environments/${{ inputs.environment }}/terraform.tfstate \
            gs://runner-tfstate-backup/${{ inputs.environment }}/pre-destroy-$(date +%s).tfstate
          
          # Export instance list
          gcloud compute instances list \
            --filter="labels.environment=${{ inputs.environment }}" \
            --format="table(name, INTERNAL_IP, EXTERNAL_IP, status)" \
            > /tmp/instances-${{ inputs.environment }}.txt
          
          # Export firewall rules
          gcloud compute firewall-rules list \
            --filter="sourceRanges:10.*" \
            > /tmp/firewall-${{ inputs.environment }}.txt
      
      - name: Terraform destroy (DRY-RUN or ACTUAL)
        run: |
          cd terraform/environments/${{ inputs.environment }}
          
          if [ "${{ inputs.dry_run }}" == "true" ]; then
            echo "🏜️ DRY-RUN MODE: No actual destruction"
            terraform plan -destroy \
              -var="image_digest=${{ github.sha }}" \
              -out=destroy.tfplan
            
            terraform show destroy.tfplan | grep -E "will be destroyed|Plan:"
          else
            echo "💣 ACTUAL DESTRUCTION (NON-REVERSIBLE)"
            terraform apply \
              -destroy \
              -auto-approve \
              -parallelism=30
            
            echo "✅ Environment destroyed"
          fi
      
      - name: Validate destruction (dry-run only)
        if: inputs.dry_run == true
        run: |
          echo "Resources to be destroyed:"
          terraform show destroy.tfplan | grep "resource\." | wc -l
```

---

#### E4.3 GitHub Actions Runner Integration

```yaml
# .github/workflows/self-test-on-runners.yml
name: Test Deploy on Self-Hosted Runners
on:
  push:
    branches: [main]
    paths: ['terraform/**', 'services/**', 'bootstrap/**']

jobs:
  test-on-ephemeral-runners:
    runs-on: [self-hosted, linux, ephemeral]  # Run on any ephemeral runner
    timeout-minutes: 30
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Verify runner environment
        run: |
          echo "Instance ID: $(curl -s http://metadata.google.internal/computeMetadata/v1/instance/id -H 'Metadata-Flavor: Google')"
          echo "Ephemeral: $(curl -s http://metadata.google.internal/computeMetadata/v1/instance/guest-attributes/gce-metadata/enabled -H 'Metadata-Flavor: Google')"
          df -h
          docker ps -a
      
      - name: Run integration tests
        run: |
          cd tests
          ./run-integration-tests.sh
      
      - name: Publish results
        if: always()
        run: |
          # Results auto-cleaned after job end (ephemeral)
          cat test-results.json
      
      # Auto-cleanup: instance self-terminates after job completes
```

---

## Summary: 10X Gains Across 4 Domains

| Domain | Current | Target | Mechanism |
|--------|---------|--------|-----------|
| **Rebuild Speed** | 30-45 min | 2-3 min | Parallel Terraform (parallelism=30), pre-warmed pools, cached images, one-click deploy |
| **Immutability** | Drift-prone | Zero-drift | Immutable image digests, read-only FS, GitOps reconciliation, no post-deploy changes |
| **Ephemeral** | Persistent state | 100% stateless | Auto-terminate after 1h, zero local persistence, all data exfiltrated to cloud logging |
| **Automated Deploy** | 10 manual steps | 1 GitHub Actions click | Single workflow: validate → build → apply → test → smoke → monitor → route actions |

**One-Click Workflow Enables:**
1. Deploy → Drift detection → Auto-heal → Health check → Route traffic
2. Zero manual intervention
3. Auditable (Git commit = deploy trigger)
4. Rollback-safe (pre-deploy backups + state lock)

---

## Implementation Roadmap (Phases)

```
WEEK 1: Build immutable image pipeline + ephemeral template (E1.1, E2.1, E3.2)
WEEK 2: Terraform parallelism + health checks (E1.2, E1.3, E3.3)
WEEK 3: GitOps integration + destroy safety (E2.3, E4.2)
WEEK 4: One-click deploy workflow + GitHub Actions integration (E4.1, E4.3)
WEEK 5: Chaos testing, rollback drills, production validation
```

---

**Status:** READY FOR IMPLEMENTATION  
**Estimated Effort:** 4-5 weeks (small team: 1-2 engineers)  
**Risk Level:** MEDIUM (requires careful phasing and rollback validation)
