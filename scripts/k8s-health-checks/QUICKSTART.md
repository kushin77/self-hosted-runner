# Quick Start Guide - Kubernetes Health Checks

## 5-Minute Setup

### 1. Verify Prerequisites
```bash
# Check kubectl is installed
kubectl version --client

# Check gcloud is installed
gcloud --version

# Check cluster access
kubectl cluster-info
```

### 2. Copy Scripts (if not already in repo)
```bash
# Scripts are in: scripts/k8s-health-checks/
ls -la scripts/k8s-health-checks/
```

### 3. Run Health Check
```bash
# Make scripts executable (if needed)
chmod +x scripts/k8s-health-checks/*.sh

# Run cluster readiness check
scripts/k8s-health-checks/cluster-readiness.sh

# Expected output (if cluster is ready):
# ✅ Cluster fully ready
# Exit code: 0
```

### 4. Run Deployment Orchestration
```bash
# Pre-deployment check
scripts/k8s-health-checks/orchestrate-deployment.sh

# Expected output:
# 🚀 Cluster is ready for deployment
# Exit code: 0
```

## Next Steps

### Option A: Use Default Configuration
```bash
# Everything works with defaults
scripts/k8s-health-checks/orchestrate-deployment.sh
```

### Option B: Custom Configuration
```bash
# Set environment variables for your setup
export PROJECT="my-project"
export CLUSTER="my-cluster"
export ZONE="us-west1-a"
export NAMESPACE="production"

scripts/k8s-health-checks/orchestrate-deployment.sh
```

### Option C: Integrate into CI/CD
See [CONFIGURATION.md](CONFIGURATION.md) for examples:
- GitHub Actions
- Cloud Build
- GitLab CI/CD
- Jenkins Pipeline

## Common Tasks

### Check if Cluster is Ready
```bash
scripts/k8s-health-checks/cluster-readiness.sh
```

### Before Deploying an Application
```bash
scripts/k8s-health-checks/orchestrate-deployment.sh || {
  echo "Cluster not ready"
  exit 1
}

# Deploy if health check passed
kubectl apply -f deployment.yaml
```

### Export Metrics to Monitoring
```bash
export PROMETHEUS_ENDPOINT="http://prometheus:9091"
scripts/k8s-health-checks/export-metrics.sh
```

### Monitor Cluster Health (Every 5 Minutes)
```bash
# Add to crontab
*/5 * * * * /path/to/scripts/k8s-health-checks/cluster-readiness.sh > /var/log/k8s-health.log 2>&1
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Command not found" | Run `chmod +x scripts/k8s-health-checks/*.sh` |
| "kubectl: not found" | Install Google Cloud SDK: `curl https://sdk.cloud.google.com \| bash` |
| "Cluster not accessible" | Check: `gcloud container clusters list` |
| "Permission denied" | Check IAM: `gcloud projects get-iam-policy $PROJECT` |

## Documentation Files

- **[README.md](README.md)** - Complete documentation
- **[CONFIGURATION.md](CONFIGURATION.md)** - Integration examples
- **[QUICKSTART.md](QUICKSTART.md)** - This file

---

**Questions or Issues?** Check the [README.md](README.md) Troubleshooting section.
