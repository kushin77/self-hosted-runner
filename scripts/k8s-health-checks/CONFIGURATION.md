# Configuration Examples

## Environment Variable Configuration

### Minimal Setup (All Defaults)
```bash
# Uses nexusshield-prod project, nexus-prod-gke cluster
scripts/k8s-health-checks/cluster-readiness.sh
```

### Custom Project & Cluster
```bash
export PROJECT="my-project"
export CLUSTER="my-gke-cluster"
export ZONE="us-west1-a"

scripts/k8s-health-checks/cluster-readiness.sh
```

### Custom Namespace & Deployment
```bash
export NAMESPACE="production"
export DEPLOYMENT_NAME="api-service"

scripts/k8s-health-checks/orchestrate-deployment.sh
```

## CI/CD Integration Examples

### GitHub Actions
```yaml
name: Deploy to GKE

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v1
        with:
          project_id: ${{ secrets.GCP_PROJECT_ID }}
          service_account_key: ${{ secrets.GCP_SA_KEY }}
          cli_version: latest
      
      - name: Get GKE credentials
        run: |
          gcloud container clusters get-credentials my-cluster \
            --zone us-central1-a \
            --project ${{ secrets.GCP_PROJECT_ID }}
      
      - name: Health check (Pre-deployment)
        run: |
          chmod +x scripts/k8s-health-checks/*.sh
          scripts/k8s-health-checks/orchestrate-deployment.sh
      
      - name: Deploy to GKE
        run: |
          kubectl apply -f k8s/
          kubectl rollout status deployment/api-service -n production
```

### Cloud Build
```yaml
steps:
  # Step 1: Build container image
  - name: "gcr.io/cloud-builders/docker"
    args: ["build", "-t", "gcr.io/$PROJECT_ID/app:$COMMIT_SHA", "."]

  # Step 2: Push to Container Registry
  - name: "gcr.io/cloud-builders/docker"
    args: ["push", "gcr.io/$PROJECT_ID/app:$COMMIT_SHA"]

  # Step 3: Get GKE credentials
  - name: "gcr.io/cloud-builders/gke-deploy"
    env:
      - "CLOUDSDK_COMPUTE_ZONE=us-central1-a"
      - "CLOUDSDK_CONTAINER_CLUSTER=nexus-prod-gke"

  # Step 4: Pre-deployment health check
  - name: "gcr.io/cloud-builders/kubectl"
    args:
      - "run"
      - "health-check"
      - "--image=gcr.io/cloud-builders/kubectl:latest"
      - "--env=PROJECT=nexusshield-prod"
      - "--env=CLUSTER=nexus-prod-gke"
      - "--env=ZONE=us-central1-a"
      - "--command"
      - "--"
      - "bash"
      - "-c"
      - "scripts/k8s-health-checks/orchestrate-deployment.sh"
    env:
      - "CLOUDSDK_COMPUTE_ZONE=us-central1-a"
      - "CLOUDSDK_CONTAINER_CLUSTER=nexus-prod-gke"

  # Step 5: Deploy
  - name: "gcr.io/cloud-builders/gke-deploy"
    args:
      - "run"
      - "--filename=k8s/"
      - "--image=gcr.io/$PROJECT_ID/app:$COMMIT_SHA"
      - "--location=us-central1-a"
      - "--cluster=nexus-prod-gke"
```

### GitLab CI/CD
```yaml
stages:
  - build
  - deploy

deploy_to_gke:
  stage: deploy
  image: google/cloud-sdk:alpine
  script:
    # Setup credentials
    - echo $GCP_SERVICE_ACCOUNT_KEY | base64 -d > ${HOME}/gcloud-service-key.json
    - gcloud auth activate-service-account --key-file ${HOME}/gcloud-service-key.json
    - gcloud config set project $GCP_PROJECT_ID
    
    # Get cluster credentials
    - gcloud container clusters get-credentials $GKE_CLUSTER --zone $GCP_ZONE
    
    # Pre-deployment health check
    - chmod +x scripts/k8s-health-checks/*.sh
    - scripts/k8s-health-checks/orchestrate-deployment.sh
    
    # Deploy
    - kubectl apply -f k8s/
    - kubectl rollout status deployment/api-service -n production
  only:
    - main
```

### Jenkins Pipeline
```groovy
pipeline {
  agent any
  
  environment {
    GCP_PROJECT_ID = credentials('gcp-project-id')
    GKE_CLUSTER = "nexus-prod-gke"
    GCP_ZONE = "us-central1-a"
    NAMESPACE = "production"
  }
  
  stages {
    stage('Setup') {
      steps {
        script {
          sh '''
            gcloud auth activate-service-account --key-file=$GOOGLE_APPLICATION_CREDENTIALS
            gcloud config set project $GCP_PROJECT_ID
            gcloud container clusters get-credentials $GKE_CLUSTER --zone $GCP_ZONE
          '''
        }
      }
    }
    
    stage('Health Check') {
      steps {
        script {
          sh '''
            chmod +x scripts/k8s-health-checks/*.sh
            scripts/k8s-health-checks/orchestrate-deployment.sh
          '''
        }
      }
    }
    
    stage('Deploy') {
      steps {
        script {
          sh '''
            kubectl apply -f k8s/
            kubectl rollout status deployment/api-service -n $NAMESPACE --timeout=5m
          '''
        }
      }
    }
  }
}
```

## Monitoring Integration

### Prometheus Pushgateway
```bash
# Export metrics to Prometheus
export PROMETHEUS_ENDPOINT="http://prometheus-pushgateway:9091"
scripts/k8s-health-checks/export-metrics.sh

# Configure in prometheus.yml:
# scrape_configs:
#   - job_name: 'k8s-health-check'
#     static_configs:
#       - targets: ['localhost:9091']
```

### Cloud Monitoring (Stackdriver)
```bash
# Automatically exports to Cloud Monitoring
export PROJECT="nexusshield-prod"
export STACKDRIVER_ENABLED="true"
scripts/k8s-health-checks/export-metrics.sh
```

### Custom HTTP Endpoint
```bash
# Send metrics to custom endpoint
export CUSTOM_ENDPOINT="https://monitoring.example.com/metrics"
scripts/k8s-health-checks/export-metrics.sh

# Receives JSON:
# {
#   "timestamp": "2026-03-14T17:15:23Z",
#   "cluster": "nexus-prod-gke",
#   "status": "ready",
#   "metrics": { ... }
# }
```

## Container Integration

### Docker Compose
```yaml
version: '3.8'
services:
  health-check:
    image: google/cloud-sdk:alpine
    volumes:
      - ./scripts/k8s-health-checks:/scripts/k8s-health-checks
    environment:
      - PROJECT=nexusshield-prod
      - CLUSTER=nexus-prod-gke
      - ZONE=us-central1-a
      - GOOGLE_APPLICATION_CREDENTIALS=/var/secrets/gcp/key.json
    volumes:
      - gcp-credentials:/var/secrets/gcp:ro
    command: /scripts/k8s-health-checks/orchestrate-deployment.sh

volumes:
  gcp-credentials:
```

### Kubernetes CronJob
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: k8s-health-check
  namespace: kube-system
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: health-check-sa
          containers:
          - name: health-check
            image: google/cloud-sdk:alpine
            command:
            - /scripts/k8s-health-checks/orchestrate-deployment.sh
            volumeMounts:
            - name: scripts
              mountPath: /scripts
            env:
            - name: PROJECT
              value: "nexusshield-prod"
            - name: CLUSTER
              value: "nexus-prod-gke"
            - name: ZONE
              value: "us-central1-a"
            - name: NAMESPACE
              value: "production"
          volumes:
          - name: scripts
            configMap:
              name: k8s-health-check-scripts
              defaultMode: 0755
          restartPolicy: OnFailure
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-health-check-scripts
  namespace: kube-system
data:
  cluster-readiness.sh: |
    # Contents of cluster-readiness.sh
  orchestrate-deployment.sh: |
    # Contents of orchestrate-deployment.sh
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: health-check-sa
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: health-check
rules:
- apiGroups: [""]
  resources: ["nodes", "pods", "namespaces"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: health-check
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: health-check
subjects:
- kind: ServiceAccount
  name: health-check-sa
  namespace: kube-system
```

## Troubleshooting Configuration

### Debug Mode
```bash
# Enable verbose output
set -x
scripts/k8s-health-checks/cluster-readiness.sh
```

### Custom Timeouts
```bash
# Increase retry delays for slow clusters
export RETRY_DELAY=30
export RETRY_COUNT=10
scripts/k8s-health-checks/cluster-readiness.sh
```

### Offline Mode (for testing)
```bash
# Test without cluster connection
kubectl version --client
echo $?  # Should return 0 if kubectl is installed
```

---

**See Also:**
- [README.md](README.md) - Main documentation
- [cluster-readiness.sh](cluster-readiness.sh) - Health check script
- [orchestrate-deployment.sh](orchestrate-deployment.sh) - Orchestration script
- [export-metrics.sh](export-metrics.sh) - Metrics exporter script
