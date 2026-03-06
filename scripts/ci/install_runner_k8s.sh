#!/usr/bin/env bash
set -euo pipefail

# install_runner_k8s.sh
# Installs GitLab Runner via Helm using the provided values template.
# Usage: ./scripts/ci/install_runner_k8s.sh path/to/values.yaml NAMESPACE

VALUES_FILE=${1:-infra/gitlab-runner/values.yaml}
NAMESPACE=${2:-gitlab-runner}
RELEASE_NAME=${3:-gitlab-runner}

if ! command -v helm >/dev/null 2>&1; then
  echo "helm not found; please install Helm v3+"
  exit 1
fi

echo "Adding/Updating gitlab Helm repo..."
helm repo add gitlab https://charts.gitlab.io || true
helm repo update

echo "Creating namespace ${NAMESPACE} if missing..."
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Installing/upgrading GitLab Runner release '${RELEASE_NAME}' in namespace '${NAMESPACE}'..."
helm upgrade --install "$RELEASE_NAME" gitlab/gitlab-runner \
  --namespace "$NAMESPACE" \
  -f "$VALUES_FILE" \
  --atomic --wait --timeout 10m

echo "Installation complete. Verify pods:"
kubectl -n "$NAMESPACE" get pods

echo "To register runners at group level, ensure 'registrationToken' is set in the values file or set via a Kubernetes secret before install."
