#!/usr/bin/env bash
set -euo pipefail

# validate_yamltest_locally.sh
# Run the commands from `YAMLtest-sovereign-runner` locally in an ephemeral
# Alpine container to validate environment commands and outputs.
# Usage: ./scripts/ci/validate_yamltest_locally.sh

docker run --rm -it alpine:latest sh -c '
  apk add --no-cache bash curl git coreutils || true
  echo "✅ Group-level runner is alive, ephemeral, and sovereign!"
  echo "Runner version: $(gitlab-runner --version 2>/dev/null || echo "gitlab-runner unavailable locally")"
  uname -a
  env | grep CI_ || echo "No CI_ env vars present in this local run"
'
