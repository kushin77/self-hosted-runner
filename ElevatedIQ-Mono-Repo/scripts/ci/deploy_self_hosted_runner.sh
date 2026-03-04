#!/bin/bash
set -e

echo "🔧 Deploying GitHub Actions self-hosted runner on .42"
echo ""

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO_URL="https://github.com/kushin77/ElevatedIQ-Mono-Repo"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: GITHUB_TOKEN not set"
    echo "Set via: export GITHUB_TOKEN=<your_token>"
    exit 1
fi

RUNNER_HOME="/opt/github-runner"
RUNNER_USER="github-runner"

echo "1️⃣ Creating runner service account..."
if ! id "$RUNNER_USER" &>/dev/null; then
    sudo useradd -m -s /bin/bash "$RUNNER_USER"
    echo "✅ Created $RUNNER_USER"
fi

echo "2️⃣ Setting up runner directory..."
sudo mkdir -p "$RUNNER_HOME"
sudo chown "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME"

echo "3️⃣ Downloading GitHub Actions runner..."
cd "$RUNNER_HOME"
sudo -u "$RUNNER_USER" bash << 'RUNNER_SETUP'
set -e
RUNNER_VERSION="2.317.0"
RUNNER_TAR="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"

if [ ! -f "$RUNNER_TAR" ]; then
    wget -q https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TAR}
fi

tar xzf "$RUNNER_TAR"
echo "✅ Runner extracted"
RUNNER_SETUP

echo "4️⃣ Configuring runner..."
sudo -u "$RUNNER_USER" bash << RUNNER_CONFIG
cd $RUNNER_HOME
./config.sh --url $REPO_URL --token $GITHUB_TOKEN --labels elevatediq,self-hosted --unattended
RUNNER_CONFIG

echo "5️⃣ Installing as systemd service..."
sudo $RUNNER_HOME/svc.sh install "$RUNNER_USER"
sudo systemctl daemon-reload
sudo systemctl enable github-runner
sudo systemctl start github-runner

echo "✅ Self-hosted runner deployed and running"
echo ""
echo "Verification:"
systemctl status github-runner
