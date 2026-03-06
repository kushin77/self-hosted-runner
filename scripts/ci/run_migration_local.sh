#!/usr/bin/env bash
set -euo pipefail

# run_migration_local.sh
# Wrapper to perform local-first GitLab Runner migration to Kubernetes.
# It intentionally requires explicit environment variables to run operations
# that use secrets or a kubeconfig so nothing is committed accidentally.
#
# Usage examples:
# 1) Dry-run only (no token/kubeconfig):
#    ./scripts/ci/run_migration_local.sh --name local-k8s-runner --url https://gitlab.example.internal
# 2) Full install (requires KUBECONFIG env and REG_TOKEN env):
#    export KUBECONFIG=/path/to/kubeconfig
#    export REG_TOKEN=xxx
#    ./scripts/ci/run_migration_local.sh --name local-k8s-runner --url https://gitlab.example.internal --out infra/gitlab-runner/values.generated.yaml

OUTFILE=${OUTFILE:-infra/gitlab-runner/values.generated.yaml}
RUNNER_NAME=${RUNNER_NAME:-local-k8s-runner}
GITLAB_URL=${GITLAB_URL:-https://gitlab.example.internal}
NAMESPACE=${NAMESPACE:-gitlab-runner}

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) RUNNER_NAME="$2"; shift 2;;
    --url) GITLAB_URL="$2"; shift 2;;
    --token) REG_TOKEN="$2"; shift 2;;
    --namespace) NAMESPACE="$2"; shift 2;;
    --out) OUTFILE="$2"; shift 2;;
    --help) echo "Usage: $0 [--name] [--url] [--namespace] [--out]"; exit 0;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

echo "Rendering values to $OUTFILE (no token stored in repo)"
./scripts/ci/generate_values_for_runner.sh --name "$RUNNER_NAME" --url "$GITLAB_URL" --token "REPLACE_ME" --namespace "$NAMESPACE" --out "$OUTFILE"

echo "Generated sample values at $OUTFILE. Edit and replace 'REPLACE_ME' with your real token or set REG_TOKEN env."

if [ -z "${REG_TOKEN:-}" ]; then
  echo "REG_TOKEN not set. To proceed with install, export REG_TOKEN and optionally set KUBECONFIG, then re-run this script or run the install script manually."
  echo
  echo "Example manual install (no commit of token):"
  echo "  export REG_TOKEN=\"<REG_TOKEN>\"" 
  echo "  ./scripts/ci/install_runner_k8s_from_secret.sh \"$REG_TOKEN\" $NAMESPACE gitlab-runner $RUNNER_NAME $GITLAB_URL"
  exit 0
fi

if [ -z "${KUBECONFIG:-}" ]; then
  echo "KUBECONFIG not set. Please export KUBECONFIG to point to your test cluster kubeconfig. Aborting install to avoid accidental cluster use."
  exit 1
fi

echo "KUBECONFIG and REG_TOKEN detected — proceeding to create secret and install."
./scripts/ci/install_runner_k8s_from_secret.sh "$REG_TOKEN" "$NAMESPACE" gitlab-runner "$RUNNER_NAME" "$GITLAB_URL"

echo "Installation complete — verify runner pods and then update your local .gitlab-ci.yml tag to match the new runner tags."
