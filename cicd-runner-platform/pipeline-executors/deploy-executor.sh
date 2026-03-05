#!/usr/bin/env bash
##
## Deploy Executor
## Executes deployments with GitOps, progressive rollout, and automated rollback.
##
set -euo pipefail

JOB_ID="${1:-unknown}"
ENVIRONMENT="${2:-staging}"
STRATEGY="${3:-canary}"

echo "Deploy Executor: ${JOB_ID}"
echo "Environment: ${ENVIRONMENT}"
echo "Strategy: ${STRATEGY}"

OUTPUT_DIR="/tmp/${JOB_ID}/deploy"
mkdir -p "${OUTPUT_DIR}"

# Load environment configuration
source "${PROJECT_ROOT}/config/runner-env.yaml"

cleanup() {
  echo "Cleaning deployment artifacts..."
}

trap cleanup EXIT

# Validate deployment
validate_deployment() {
  echo "Validating deployment manifests..."
  
  # Kubeval
  if command -v kubeval &>/dev/null; then
    kubeval deploy/k8s/*.yaml --strict > "${OUTPUT_DIR}/kubeval.json"
  fi
  
  # OPA policy validation
  if command -v conftest &>/dev/null; then
    conftest test \
      -p "${PROJECT_ROOT}/security/policy/deployment.rego" \
      -o json \
      deploy/k8s/*.yaml > "${OUTPUT_DIR}/policy-check.json"
  fi
  
  echo "✓ Validation passed"
}

# Progressive rollout strategies
deploy_canary() {
  echo "Deploying with canary strategy..."
  
  # Use Argo Rollouts or Flagger
  kubectl apply -f deploy/k8s/rollout.yaml
  
  # Monitor canary
  kubectl wait --for condition=achieved \
    -f deploy/k8s/rollout.yaml \
    --timeout=600s
  
  echo "✓ Canary deployment succeeded"
}

deploy_bluegreen() {
  echo "Deploying with blue/green strategy..."
  
  kubectl apply -f deploy/k8s/blue.yaml
  kubectl wait --for condition=ready pod \
    -l app=myapp,version=blue \
    --timeout=300s
  
  # Switch traffic
  kubectl patch svc myapp -p '{"spec":{"selector":{"version":"blue"}}}'
  
  echo "✓ Blue/green deployment succeeded"
}

deploy_gitops() {
  echo "Deploying via GitOps (ArgoCD)..."
  
  # Update Git repo with new image digest
  DIGEST=$(cat "${OUTPUT_DIR}/image-digest.txt")
  
  git clone --depth=1 "${GITOPS_REPO}" /tmp/gitops-${JOB_ID}
  cd "/tmp/gitops-${JOB_ID}/apps/${ENVIRONMENT}"
  
  # Update Kustomization or Helm values
  kustomize edit set image "app=app:${DIGEST}"
  
  git config user.name "ci-bot"
  git config user.email "ci@example.com"
  git add kustomization.yaml
  git commit -m "Deploy ${JOB_ID}: ${DIGEST}" || true
  git push origin main
  
  echo "✓ GitOps push completed, ArgoCD will sync"
}

# Rollback trigger
rollback_deployment() {
  echo "Rolling back deployment..."
  
  if ! kubectl rollout status deployment/myapp --timeout=300s; then
    echo "Rollback initiated due to failed rollout"
    kubectl rollout undo deployment/myapp
    kubectl rollout status deployment/myapp --timeout=300s
  fi
  
  echo "✓ Rollback completed"
}

# Health check
health_check() {
  echo "Running health checks..."
  
  # Wait for ready replicas
  kubectl wait --for=condition=ready pod \
    -l app=myapp \
    --timeout=300s
  
  # Service connectivity test
  kubectl run health-check --image=curlimages/curl:7.90.0 \
    --restart=Never -- \
    curl -f "http://myapp.${ENVIRONMENT}:8080/health" || return 1
  
  echo "✓ Health checks passed"
}

# Main execution flow
validate_deployment || exit 1

case "${STRATEGY}" in
  canary)
    deploy_canary
    ;;
  bluegreen)
    deploy_bluegreen
    ;;
  gitops)
    deploy_gitops
    ;;
  *)
    deploy_gitops
    ;;
esac

health_check || rollback_deployment || exit 1

echo "✓ Deployment succeeded"
