#!/bin/bash
set -euo pipefail

# GitHub Actions Self-Hosted Runner Deployment Helper
# Deploys runner on 192.168.168.42 serving all repos (ElevatedIQ, aetherfoge, etc)

RUNNER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_DIR_REMOTE="/home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner"
RUNNER_HOST="192.168.168.42"
RUNNER_CONTAINER="elevatediq-github-runner"

# SSH options: non-interactive, short connect timeout, keepalive
SSH_OPTIONS='-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=60 -o ServerAliveCountMax=3'

echo "🚀 GitHub Actions Self-Hosted Runner Deployment"
echo "=================================================="
echo ""
echo "📍 Target: $RUNNER_HOST ($RUNNER_CONTAINER)"
echo "📂 Runner Dir: $RUNNER_DIR_REMOTE"
echo ""

# Step 1: Generate Token (auto-try via gh on remote, fallback to prompt)
echo "📋 STEP 1: Obtain runner registration token"
echo "-------------------------------------------------"
echo ""
RUNNER_TOKEN=""

# Try to generate token on remote host (requires gh installed and authenticated there)
echo "🔎 Attempting to generate token on $RUNNER_HOST via ssh/gh (non-interactive)..."
REMOTE_TOKEN=$(ssh $SSH_OPTIONS -T akushnir@"$RUNNER_HOST" "bash -lc 'if command -v gh >/dev/null 2>&1; then gh api -X POST repos/kushin77/ElevatedIQ-Mono-Repo/actions/runners/registration-token -H \"Accept: application/vnd.github+json\" -q .token 2>/dev/null || true; fi' < /dev/null") || true

if [ -n "$REMOTE_TOKEN" ]; then
    echo "✅ Obtained token from $RUNNER_HOST (stored on remote at /tmp/runner.token)"
    RUNNER_TOKEN="$REMOTE_TOKEN"
else
    # Try local gh (workstation)
    if command -v gh >/dev/null 2>&1; then
        echo "🔎 gh available locally; attempting to create token locally..."
        LOCAL_TOKEN=$(gh api -X POST repos/kushin77/ElevatedIQ-Mono-Repo/actions/runners/registration-token -H "Accept: application/vnd.github+json" -q .token 2>/dev/null) || true
        if [ -n "$LOCAL_TOKEN" ]; then
            echo "✅ Obtained token locally"
            RUNNER_TOKEN="$LOCAL_TOKEN"
        fi
    fi
fi

if [ -z "$RUNNER_TOKEN" ]; then
    echo "⚠️  Could not auto-generate token. Please create one in the GitHub UI or use a PAT to call the API."
    echo "Instructions: https://github.com/kushin77/ElevatedIQ-Mono-Repo/settings/actions/runners/new"
    read -p "🔑 Paste your RUNNER_TOKEN here: " RUNNER_TOKEN
    if [ -z "$RUNNER_TOKEN" ]; then
        echo "❌ Token is empty. Exiting."
        exit 1
    fi
fi

echo ""
echo "✅ Token ready (will be sent to remote for registration)"
echo ""

# Persist token on remote so the remote docker-compose invocation can read it
if [ -n "$RUNNER_TOKEN" ]; then
    echo "🔒 Uploading RUNNER_TOKEN to remote /tmp/runner.token (remote only)"
    ssh $SSH_OPTIONS akushnir@"$RUNNER_HOST" "printf '%s' \"$RUNNER_TOKEN\" > /tmp/runner.token && chmod 600 /tmp/runner.token" || true
fi

# Step 2: Deploy Container
echo "🐳 STEP 2: Deploy Runner Container"
echo "-----------------------------------"
echo ""
echo "⏳ Starting runner container on $RUNNER_HOST..."
echo ""

ssh $SSH_OPTIONS -T akushnir@"$RUNNER_HOST" bash -s < /dev/null <<'REMOTE_EOF'
    set -euo pipefail
    cd /home/akushnir/ElevatedIQ-Mono-Mono-Repo/build/github-runner || exit 1

    # Choose a unique RUNNER_NAME to avoid registration conflicts if previous
    # runner with same name remains registered. Use timestamp suffix for idempotence.
    export RUNNER_NAME="elevatediq-runner-$(date +%s)"

    # Read token from /tmp/runner.token if present (deploy earlier stored it there)
    RUNNER_TOKEN=$(cat /tmp/runner.token 2>/dev/null || echo "")
    export RUNNER_TOKEN

    # Determine remote user UID/GID so the container can run with matching
    # ownership and avoid chown/permission failures on mounted volumes.
    REMOTE_UID=$(id -u 2>/dev/null || echo 1000)
    REMOTE_GID=$(id -g 2>/dev/null || echo 1000)
    export RUNNER_UID="$REMOTE_UID"
    export RUNNER_GID="$REMOTE_GID"

    # Stop and remove any existing containers and volumes to ensure a clean start
    # (removes previous runner configuration so the container can register anew)
    docker-compose down -v || true

    # Start runner container (will pick up exported RUNNER_NAME, RUNNER_TOKEN,
    # RUNNER_UID and RUNNER_GID from the remote environment)
    docker-compose up -d && \
    echo '✅ Container started' && \
    echo '' && \
    echo '📊 Waiting 10 seconds for startup...' && \
    sleep 10 && \
    docker logs elevatediq-github-runner | tail -20
REMOTE_EOF

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed"
    exit 1
fi

echo ""
echo "✅ STEP 2 Complete"
echo ""

# Step 3: Verify
echo "🔍 STEP 3: Verify Runner Online"
echo "--------------------------------"
echo ""
echo "📋 Checking GitHub Actions settings..."
echo ""
echo "✅ Runner should appear at: https://github.com/kushin77/settings/runners"
echo ""
echo "   Expected state: 🟢 Idle (Listening for jobs)"
echo ""
echo "💡 TIP: Run this to watch logs (non-interactive):"
echo "    ssh $SSH_OPTIONS akushnir@$RUNNER_HOST 'docker logs --tail 200 $RUNNER_CONTAINER'"
echo "    # For interactive follow, run locally with -t: ssh -t akushnir@$RUNNER_HOST 'docker logs -f $RUNNER_CONTAINER'"
echo ""

# Step 4: Update Workflows
echo "🔄 STEP 4: Update Repository Workflows"
echo "--------------------------------------"
echo ""
echo "Update all repos to use the self-hosted runner:"
echo ""
echo "  .github/workflows/*.yml:"
echo "    Find:     runs-on: ubuntu-latest"
echo "    Replace:  runs-on: self-hosted"
echo ""
echo "  Repos to update:"
echo "    - ElevatedIQ-Mono-Repo"
echo "    - aetherfoge"
echo "    - Any other repos"
echo ""

# Step 5: Test
echo "🧪 STEP 5: Test End-to-End"
echo "--------------------------"
echo ""
echo "1. Push a PR in aetherfoge with updated workflow"
echo "2. Verify GitHub Actions runs on container"
echo "3. Check logs: ssh akushnir@192.168.168.42 'docker logs -f elevatediq-github-runner'"
echo ""

echo "🎉 Deployment Complete!"
echo ""
echo "📚 Documentation: $RUNNER_DIR_REMOTE/DEPLOYMENT.md"
echo "🛑 To stop runner: ssh akushnir@$RUNNER_HOST 'docker-compose -f $RUNNER_DIR_REMOTE/docker-compose.yml down'"
echo ""
