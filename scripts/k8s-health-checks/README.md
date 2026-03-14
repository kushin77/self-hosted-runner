# Kubernetes Health Checks & Deployment Orchestration

## Overview

This system provides production-grade health checks and orchestration for Kubernetes deployments. It ensures your cluster is ready before deployment and handles retries automatically.

**Key Features:**
- ✅ Fully idempotent (safe to run multiple times)
- ✅ GSM-based credentials (no manual secrets)
- ✅ Automatic retry logic with exponential backoff
- ✅ Comprehensive health checks
- ✅ Clear status reporting

## Architecture

### 1. Cluster Readiness Probe (`cluster-readiness.sh`)

Comprehensive health check that verifies:

| Check | Purpose | Success Criteria |
|-------|---------|------------------|
| **Cluster Accessible** | GKE cluster connectivity | Describe call succeeds |
| **API Server Health** | Kubernetes API server status | kubectl cluster-info returns master |
| **Node Readiness** | Worker node status | At least 1 node in Ready state |
| **Core Namespaces** | Essential namespaces exist | default, kube-system, kube-public |
| **System Pods** | Critical system components running | At least 1 pod running in kube-system |

**Exit Codes:**
- `0`: Fully ready (all 5 checks passed)
- `1`: Partially ready (3-4 checks passed)
- `2`: Not ready (< 3 checks passed)

### 2. Deployment Orchestration (`orchestrate-deployment.sh`)

4-phase orchestration pipeline:

1. **Cluster Readiness**: Validates cluster health before proceeding
2. **Namespace Verification**: Creates/verifies target namespace
3. **Pre-deployment Validation**: Checks RBAC permissions
4. **Readiness Summary**: Reports final status

## Usage

### Basic Cluster Readiness Check

```bash
# Check if cluster is ready
scripts/k8s-health-checks/cluster-readiness.sh

# With environment variables
CLUSTER="my-cluster" ZONE="us-west1-a" \
  scripts/k8s-health-checks/cluster-readiness.sh
```

### Pre-deployment Orchestration

```bash
# Standard deployment prep
scripts/k8s-health-checks/orchestrate-deployment.sh

# With custom namespace
NAMESPACE="production" scripts/k8s-health-checks/orchestrate-deployment.sh

# With custom deployment name
DEPLOYMENT_NAME="my-service" \
  scripts/k8s-health-checks/orchestrate-deployment.sh
```

### In CI/CD Pipeline

```yaml
# Example: Cloud Build step
- name: "gcr.io/cloud-builders/gke-deploy"
  args:
    - "run"
    - "--filename=k8s/"
    - "--image=gcr.io/$PROJECT_ID/my-app:$COMMIT_SHA"
    - "--location=us-central1-a"
    - "--cluster=my-cluster"
  env:
    - "CLOUDSDK_COMPUTE_ZONE=us-central1-a"
    - "CLOUDSDK_CONTAINER_CLUSTER=my-cluster"
  entrypoint: bash
  args:
    - -c
    - |
      # Pre-deployment health check
      scripts/k8s-health-checks/orchestrate-deployment.sh || exit 1
      
      # Proceed with deployment
      gke-deploy run ...
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT` | `nexusshield-prod` | GCP project ID |
| `CLUSTER` | `nexus-prod-gke` | GKE cluster name |
| `ZONE` | `us-central1-a` | GCP zone |
| `NAMESPACE` | `default` | Kubernetes namespace |
| `DEPLOYMENT_NAME` | `nexus-app` | Deployment resource name |
| `TIMEOUT` | `300` | Timeout in seconds |
| `RETRY_DELAY` | `10` | Delay between retries |
| `RETRY_COUNT` | `5` | Maximum retry attempts |

### Updating Defaults

Edit the script constants:

```bash
# In cluster-readiness.sh
PROJECT="your-project"
CLUSTER="your-cluster"
ZONE="your-zone"
```

## Output Examples

### Successful Full Readiness

```
🔍 Kubernetes Cluster Readiness Check
  Cluster: nexus-prod-gke (Zone: us-central1-a)
  Project: nexusshield-prod
  Timestamp: 2026-03-14T17:15:23Z

✅ Cluster accessible
✅ API Server healthy
✅ Nodes ready: 3/3
✅ Namespace default exists
✅ Namespace kube-system exists
✅ Namespace kube-public exists
✅ System pods running: 12

📊 Results: 6/6 checks passed
✅ Cluster fully ready
```

### Partial Readiness

```
🔍 Kubernetes Cluster Readiness Check
  ...

✅ Cluster accessible
✅ API Server healthy
⚠️ Nodes not ready: 1/3
✅ Namespace default exists
✅ Namespace kube-system exists
✅ Namespace kube-public exists
⚠️ No running system pods detected

📊 Results: 4/6 checks passed
⚠️ Cluster partially ready
```

## Troubleshooting

### "Cluster not accessible after 5 attempts"

**Cause**: GKE cluster is not responding

**Solutions**:
1. Verify cluster exists: `gcloud container clusters list`
2. Check GCP project: `gcloud config get-value project`
3. Verify zone config: `gcloud config get-value compute/zone`
4. Check IAM permissions: `gcloud projects get-iam-policy $PROJECT`

### "API Server health check inconclusive"

**Cause**: kubectl cluster-info output format differs

**Solutions**:
1. Verify kubectl is configured: `kubectl config current-context`
2. Test directly: `kubectl cluster-info`
3. Update check regex if output format differs

### "Nodes not ready"

**Cause**: GKE node pool scaling or initialization

**Solutions**:
1. Check node status: `kubectl get nodes -o wide`
2. View node events: `kubectl describe nodes`
3. Wait for auto-scaling: retry after 30 seconds
4. Check node pool status: `gcloud container node-pools list --cluster=$CLUSTER`

### "No running system pods"

**Cause**: Critical system pods crashed or evicted

**Solutions**:
1. List all system pods: `kubectl get pods -n kube-system`
2. Check events: `kubectl get events -n kube-system`
3. Restart system: Contact GKE support
4. Recreate cluster if persistent

## Best Practices

### 1. Run Before Every Deployment
```bash
# Ensure consistency
scripts/k8s-health-checks/orchestrate-deployment.sh || {
  echo "❌ Cluster not ready, deployment blocked"
  exit 1
}
# Deploy only if health check passed
```

### 2. Idempotency
These scripts are idempotent - safe to run multiple times:
```bash
# Run 5 times, all succeed
for i in {1..5}; do
  scripts/k8s-health-checks/cluster-readiness.sh
done
```

### 3. Integration with Deployment Tools

**ArgoCD**: Add as pre-sync hook
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
spec:
  syncPolicy:
    syncOptions:
    - Validate=false
    presync:
    - command: /scripts/k8s-health-checks/orchestrate-deployment.sh
```

**Helm**: Include as init job
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: health-check
spec:
  template:
    spec:
      initContainers:
      - name: health-check
        image: gcr.io/google.com/cloudsdktool/cloud-sdk:alpine
        command: ["/scripts/k8s-health-checks/cluster-readiness.sh"]
```

### 4. Monitoring Integration

Track health checks in your monitoring system:
```bash
# Export metrics
scripts/k8s-health-checks/cluster-readiness.sh > /tmp/health.log 2>&1
EXIT_CODE=$?
echo "k8s_health_check_exit{cluster=\"nexus-prod-gke\"} $EXIT_CODE" | \
  curl -X POST --data-binary @- http://prometheus:9091/metrics/job/k8s-health
```

## Security Considerations

### Credentials
- ✅ No plaintext credentials in scripts
- ✅ Credentials from Google Secret Manager (GSM)
- ✅ gcloud CLI uses workload identity
- ✅ Safe to commit to source control

### RBAC
- Script checks `get deployments` permission
- Extends to required permissions as needed
- Runs as authenticated GCP service account

### Logging
- All output is debug-safe (no secrets printed)
- Timestamps for audit trails
- Status codes for integration with alerting

## Maintenance

### Updating Check Logic

Each check is self-contained:
```bash
check_api_server() {
  # Update logic here
  # Return 0 for success, 1 for failure
}
```

### Adding New Checks

1. Create new function
2. Call in main loop
3. Increment checks_total
4. Update documentation

Example:
```bash
check_storage_available() {
  # Your check logic
  return 0
}

# In main():
check_storage_available && ((checks_passed++)) || true
((checks_total++))
```

## Performance Metrics

| Operation | Typical Duration | Max Duration |
|-----------|-----------------|--------------|
| Cluster accessible check | 1-2s | 50s (5 retries) |
| API server health | 0.5s | 5s |
| Node readiness | 1-2s | 10s |
| Namespace check | 1-2s | 10s |
| System pods check | 1-2s | 10s |
| **Full health check** | **10-15s** | **5-10 min** |

## Support & Resolution

For issues or questions:
1. Check output for specific failed check
2. Refer to Troubleshooting section
3. Verify environment variables
4. Consult GKE documentation
5. Open issue in repository

---

**Version**: 1.0  
**Last Updated**: 2026-03-14  
**Maintainer**: NexusShield Platform Team
