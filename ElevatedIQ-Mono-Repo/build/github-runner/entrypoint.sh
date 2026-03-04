#!/bin/bash
set -euo pipefail

# GitHub Actions Runner Entrypoint
# This script registers the runner with GitHub and starts the listener

RUNNER_NAME="${RUNNER_NAME:-github-runner-$(hostname)}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-./_work}"
GITHUB_URL="${GITHUB_URL:-https://github.com/kushin77}"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,x64,docker}"

echo "=========================================="
echo "GitHub Actions Self-Hosted Runner"
echo "=========================================="
echo "Name: $RUNNER_NAME"
echo "URL: $GITHUB_URL"
echo "Labels: $RUNNER_LABELS"
echo "Work Dir: $RUNNER_WORKDIR"
echo "=========================================="

# Check if already configured
if [ -f "/runner/.configured" ]; then
    echo "✓ Runner already configured. Starting listener..."
    cd /runner
    ./run.sh
    exit 0
fi

# Validate token provided
if [ -z "$RUNNER_TOKEN" ]; then
    echo "❌ ERROR: RUNNER_TOKEN environment variable not set"
    echo "Get token from: https://github.com/kushin77/settings/runners/new"
    echo "Run: docker run -e RUNNER_TOKEN=ghp_xxx ... "
    exit 1
fi

echo ""
echo "🔧 Configuring runner..."
cd /runner

# Configure runner (non-interactive)
./config.sh \
    --url "$GITHUB_URL" \
    --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" \
    --work "$RUNNER_WORKDIR" \
    --labels "$RUNNER_LABELS" \
    --unattended \
    --replace

echo ""
echo "✓ Configuration complete"
echo "✓ Marking as configured"
touch /runner/.configured

echo ""
echo "🚀 Starting GitHub Actions listener..."
./run.sh
