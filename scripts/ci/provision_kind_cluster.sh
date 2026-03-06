#!/usr/bin/env bash
set -euo pipefail

# provision_kind_cluster.sh
# Provision a local KinD cluster for smoke-testing the GitLab Runner deployment.
# Does not install Docker or Kind automatically; it checks prerequisites and
# prints exact commands to run if missing.
# Usage: ./scripts/ci/provision_kind_cluster.sh [cluster-name]

CLUSTER_NAME=${1:-gitlab-runner-test}
KIND_BIN=${KIND_BIN:-$(command -v kind || true)}

echo "Provisioning KinD cluster: ${CLUSTER_NAME}"

if [ -z "${KIND_BIN}" ]; then
  echo "Kind binary not found in PATH. Install kind (https://kind.sigs.k8s.io/) first." >&2
  echo "Suggested install (Linux):"
  echo "  curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind"
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. A container runtime (Docker) is required to create KinD clusters." >&2
  echo "Install Docker Engine or use an alternative (k3d)." >&2
  exit 2
fi

echo "Creating kind cluster '${CLUSTER_NAME}' (this may take a few minutes)..."
${KIND_BIN} create cluster --name "${CLUSTER_NAME}" --wait 2m

echo "Kind cluster created. Exporting kubeconfig context..."
kubectl cluster-info --context kind-${CLUSTER_NAME} >/dev/null 2>&1 || true
echo "To use the cluster:"
echo "  export KUBECONFIG=\"$(kind get kubeconfig-path --name="${CLUSTER_NAME}" 2>/dev/null || echo '~/.kube/config')\""
echo "Or merge with your existing kubeconfig as desired."

echo "Cluster nodes:"
kubectl get nodes --context kind-${CLUSTER_NAME}

echo "KinD provisioner complete. Run the hands-off deploy once the registration secret is applied."
