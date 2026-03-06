#!/usr/bin/env bash
set -euo pipefail
# bootstrap-runner.sh
# Bootstraps and registers a GitHub Actions self-hosted runner on a Linux host.

OWNER=${RUNNER_OWNER:-}
REPO=${RUNNER_REPO:-}
TOKEN=${RUNNER_TOKEN:-}
VERSION=${RUNNER_VERSION:-2.332.0}
LABELS=${RUNNER_LABELS:-"self-hosted,on-prem,linux"}
NAME=${RUNNER_NAME:-"onprem-$(hostname)"}
WORKDIR=${RUNNER_DIR:-/opt/actions-runner}

if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
  echo "RUNNER_OWNER and RUNNER_REPO required (export RUNNER_OWNER/REPO)" >&2
  exit 1
fi

if [ -z "$TOKEN" ]; then
  echo "Fetching runner token via scripts/fetch-runner-token.sh"
  TOKEN=$(bash $(dirname "$0")/fetch-runner-token.sh)
fi

if [ -z "$TOKEN" ]; then
  echo "No runner token found. Provide RUNNER_TOKEN or configure Vault variables." >&2
  exit 1
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

ARCH=$([ "$(uname -m)" = "aarch64" ] && echo "arm64" || echo "x64")
URL="https://github.com/actions/runner/releases/download/v${VERSION}/actions-runner-linux-${ARCH}-${VERSION}.tar.gz"

download_with_retries() {
    local url="$1" dest="$2" i
    for i in 1 2 3; do
        if curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$dest"; then
            return 0
        fi
        sleep $((i * 2))
    done
    return 1
}

echo "Downloading runner from $URL"
if ! download_with_retries "$URL" actions-runner.tar.gz; then
    echo "Failed to download runner from $URL" >&2
    exit 1
fi
tar xzf actions-runner.tar.gz

echo "Configuring runner for https://github.com/${OWNER}/${REPO}"
./config.sh --unattended --url "https://github.com/${OWNER}/${REPO}" --token "$TOKEN" --name "$NAME" --labels "$LABELS" --work _work

echo "Installing and starting runner service"
sudo ./svc.sh install
sudo ./svc.sh start

echo "Runner bootstrap complete: $NAME"
