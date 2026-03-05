#!/usr/bin/env bash
set -euo pipefail

# fetch-runner-binaries.sh
# Minimal helper to download required runner binaries at CI/runtime instead of committing them.
# Usage: RUNNER_VARIANT=node24 ./scripts/fetch-runner-binaries.sh /tmp/runners

OUT_DIR=${1:-.}
RUNNER_VARIANT=${RUNNER_VARIANT:-node24}

# Default mapping - update these URLs to your release storage (S3, GH Releases, internal mirror)
declare -A URLS
URLS[node20_alpine]="https://example.com/releases/actions-runner-node20-alpine.tar.gz"
URLS[node20]="https://example.com/releases/actions-runner-node20.tar.gz"
URLS[node24_alpine]="https://example.com/releases/actions-runner-node24-alpine.tar.gz"
URLS[node24]="https://example.com/releases/actions-runner-node24.tar.gz"

URL=${URLS[${RUNNER_VARIANT}]}
if [ -z "$URL" ]; then
  echo "Unknown RUNNER_VARIANT: $RUNNER_VARIANT"
  exit 2
fi

mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

echo "Downloading runner variant $RUNNER_VARIANT from $URL"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o runner.tar.gz "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O runner.tar.gz "$URL"
else
  echo "curl or wget required to fetch runner binaries"
  exit 3
fi

echo "Extracting..."
mkdir -p runner
tar -xzf runner.tar.gz -C runner --strip-components=0
rm -f runner.tar.gz

echo "Runner binaries fetched to $OUT_DIR/runner"

# Example: export RUNNER_DIR="$OUT_DIR/runner" for downstream scripts
