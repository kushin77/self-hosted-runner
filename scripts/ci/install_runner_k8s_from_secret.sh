#!/usr/bin/env bash
set -euo pipefail

# install_runner_k8s_from_secret.sh
# Create a Kubernetes secret containing the registration token and install/upgrade
# the GitLab Runner Helm release using a generated values file that references
# the token. This keeps the token out of VCS.
# Usage: ./scripts/ci/install_runner_k8s_from_secret.sh <REG_TOKEN> [NAMESPACE] [RELEASE]

REG_TOKEN=${1:-}
NAMESPACE=${2:-gitlab-runner}
RELEASE=${3:-gitlab-runner}
RUNNER_NAME=${4:-local-k8s-runner}
GITLAB_URL=${5:-https://gitlab.example.internal}

if [ -z "$REG_TOKEN" ]; then
  echo "Usage: $0 <REG_TOKEN> [NAMESPACE] [RELEASE] [RUNNER_NAME] [GITLAB_URL]"
  exit 1
fi

echo "Creating namespace: $NAMESPACE (if missing)"
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Creating Kubernetes secret with registration token (gitlab-runner-regtoken)..."
kubectl -n "$NAMESPACE" create secret generic gitlab-runner-regtoken --from-literal=registrationToken="$REG_TOKEN" --dry-run=client -o yaml | kubectl apply -f -

VALUES_OUT=$(mktemp /tmp/values.generated.XXXX.yaml)
trap 'rm -f "$VALUES_OUT"' EXIT

cat > "$VALUES_OUT" <<EOF
replicaCount: 1
serviceAccount:
  create: true
  name: gitlab-runner
runners:
  image: "gitlab/gitlab-runner:alpine"
  privileged: false
  config: |
    [[runners]]
      name = "${RUNNER_NAME}"
      url = "${GITLAB_URL}"
      executor = "kubernetes"
      tags = "k8s-runner,ephemeral,sovereign"
      [runners.kubernetes]
        namespace = "${NAMESPACE}"
        image = "docker:24.0.5"
        privileged = false
  registrationToken: "$(kubectl -n "$NAMESPACE" get secret gitlab-runner-regtoken -o jsonpath='{.data.registrationToken}' | base64 --decode)"
  concurrent: 10
  checkInterval: 30
EOF

echo "Installing/upgrading Helm release $RELEASE in $NAMESPACE using temporary values file"
helm repo add gitlab https://charts.gitlab.io || true
helm repo update
helm upgrade --install "$RELEASE" gitlab/gitlab-runner --namespace "$NAMESPACE" -f "$VALUES_OUT" --atomic --wait --timeout 10m

echo "Helm install complete. Verify pods:"
kubectl -n "$NAMESPACE" get pods

echo "NOTE: Secret 'gitlab-runner-regtoken' exists in namespace $NAMESPACE. Delete or rotate after install if desired."
