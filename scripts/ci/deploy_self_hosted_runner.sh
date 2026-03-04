#!/bin/bash
set -e

echo "🔧 Deploying GitHub Actions self-hosted runner on .42"
echo ""

# allow token passthrough or generation via gh
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO_URL="https://github.com/kushin77/ElevatedIQ-Mono-Repo"

if [ -z "$GITHUB_TOKEN" ]; then
    # try to create registration token using gh CLI
    if command -v gh >/dev/null 2>&1; then
        echo "🔑 No GITHUB_TOKEN provided, attempting gh CLI registration"
        GITHUB_TOKEN=$(gh api -X POST "/repos/kushin77/ElevatedIQ-Mono-Repo/actions/runners/registration-token" --jq '.token' 2>/dev/null || true)
        if [ -n "$GITHUB_TOKEN" ]; then
            echo "✅ obtained token via gh CLI"
        fi
    fi
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN not set and gh CLI failed"
    echo "Set via: export GITHUB_TOKEN=<your_token> or login via gh auth login"
    exit 1
fi

# forward to more robust phase‑2 installer

# the phase_2_runner_install.sh script already handles download, config,
# service creation, restart policies, and maintenance timer. simply call it
# with whatever token we have (empty is ok if gh CLI auth exists).
SCRIPT="/home/akushnir/ElevatedIQ-Mono-Mono-Repo/scripts/automation/pmo/phase_2_runner_install.sh"

if [ -x "$SCRIPT" ]; then
    bash "$SCRIPT" "$GITHUB_TOKEN"
else
    echo "❌ cannot find installer at $SCRIPT"
    exit 1
fi
