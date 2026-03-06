#!/usr/bin/env bash
set -euo pipefail

# generate_values_for_runner.sh
# Generate a local values.yaml from the template by replacing placeholders.
# Usage: ./scripts/ci/generate_values_for_runner.sh --name runner-name --url https://gitlab.example --token xxxxx --namespace gitlab-runner > infra/gitlab-runner/values.yaml

while [[ $# -gt 0 ]]; do
  case $1 in
    --name) RUNNER_NAME="$2"; shift 2;;
    --url) GITLAB_URL="$2"; shift 2;;
    --token) REGISTRATION_TOKEN="$2"; shift 2;;
    --namespace) RUNNER_K8S_NAMESPACE="$2"; shift 2;;
    --out) OUTFILE="$2"; shift 2;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

: ${RUNNER_NAME:?}
: ${GITLAB_URL:?}
: ${REGISTRATION_TOKEN:?}
: ${RUNNER_K8S_NAMESPACE:=gitlab-runner}
OUTFILE=${OUTFILE:-infra/gitlab-runner/values.generated.yaml}

sed \
  -e "s|{{RUNNER_NAME}}|${RUNNER_NAME}|g" \
  -e "s|{{GITLAB_URL}}|${GITLAB_URL}|g" \
  -e "s|{{REGISTRATION_TOKEN}}|${REGISTRATION_TOKEN}|g" \
  -e "s|{{RUNNER_K8S_NAMESPACE}}|${RUNNER_K8S_NAMESPACE}|g" \
  infra/gitlab-runner/values.yaml.template > "$OUTFILE"

echo "Generated $OUTFILE"
