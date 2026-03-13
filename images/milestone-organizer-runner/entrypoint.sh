#!/bin/bash
set -euo pipefail

WORKDIR=/workspace
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Ensure repo is present
if [ ! -d repo ]; then
  git clone https://github.com/kushin77/self-hosted-runner.git repo
else
  cd repo && git fetch --all --prune || true && git reset --hard origin/main || true
  cd ..
fi

cd repo || exit 1

# If CSI mounted secret exists, export it for tools that expect GH_TOKEN env
if [ -f /var/run/secrets/gh_token ]; then
  export GH_TOKEN=$(cat /var/run/secrets/gh_token)
fi

# Run the wrapper
exec ./scripts/automation/run_milestone_organizer.sh
