#!/usr/bin/env bash
set -euo pipefail

# hands_off_runner_deploy.sh
# Final autonomous deployment of the sovereign, ephemeral GitLab Runner.
# Ensures idempotency, immutable config, and independent ops.

NAMESPACE="gitlab-runner"
RELEASE="gitlab-runner"
RUNNER_NAME="sovereign-ephemeral-k8s-runner"
GITLAB_URL="https://gitlab.internal.elevatediq.com"

echo "Step 1: Resource Isolation & Namespace Setup"
kubectl create ns "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Step 2: Credential Check (Independent Ops)"
if ! kubectl -n "$NAMESPACE" get secret gitlab-runner-regtoken >/dev/null 2>&1; then
  echo "ERROR: Registration secret 'gitlab-runner-regtoken' missing in $NAMESPACE."
  echo "Autonomous run requires the secret to be pre-provisioned via SealedSecret or manual setup."
  exit 1
fi

echo "Step 3: Rendering Immutable Helm Configuration"
VALUES_FILE="infra/gitlab-runner/values.hands-off.yaml"
cat > "$VALUES_FILE" <<INNER_EOF
replicaCount: 1
gitlabUrl: ${GITLAB_URL}
runnerRegistrationToken: "" # Left empty as we use the pre-existing secret
existingSecret: "gitlab-runner-regtoken"

serviceAccount:
  create: true
  name: gitlab-runner

runners:
  image: "gitlab/gitlab-runner:alpine"
  privileged: false
  tags: "k8s-runner,ephemeral,sovereign"
  runUntagged: false
  config: |
    [[runners]]
      name = "${RUNNER_NAME}"
      executor = "kubernetes"
      [runners.kubernetes]
        namespace = "${NAMESPACE}"
        image = "docker:24.0.5"
        privileged = false
        cpu_limit = "1"
        memory_limit = "2Gi"
        service_cpu_limit = "1"
        service_memory_limit = "2Gi"
        helper_cpu_limit = "500m"
        helper_memory_limit = "512Mi"
        poll_interval = 5
        poll_timeout = 3600
  concurrent: 10
  checkInterval: 30
INNER_EOF

echo "Step 4: Executing Sovereign Deployment (Helm)"
helm repo add gitlab https://charts.gitlab.io || true
helm repo update
helm upgrade --install "$RELEASE" gitlab/gitlab-runner \
  --namespace "$NAMESPACE" \
  -f "$VALUES_FILE" \
  --atomic --wait --timeout 5m

echo "Step 5: Post-Deployment Verification"
kubectl -n "$NAMESPACE" get pods -l "app=gitlab-runner"
echo "Deployment successful. Runner is ready for hands-off ephemeral execution."
