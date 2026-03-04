#!/usr/bin/env bash
# Build the Packer AMI for Ollama-enabled runners

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKER_DIR="$REPO_ROOT/packer"

usage() {
  echo "Usage: $0 [--no-run]"
  echo "  --no-run   : Print the packer command but don't execute it"
  exit 1
}

NO_RUN=0
if [ "${1-}" = "--no-run" ]; then
  NO_RUN=1
fi

if ! command -v packer >/dev/null 2>&1; then
  echo "Error: 'packer' not found in PATH. Install Packer (recommended >=1.8) and retry." >&2
  exit 2
fi

cd "$PACKER_DIR"

BUILD_ID=$(date +%s)
CMD=(packer build -var "build_id=${BUILD_ID}" runner-image.pkr.hcl)

echo "Packer command: ${CMD[*]}"

if [ "$NO_RUN" -eq 1 ]; then
  echo "Dry-run mode; not executing packer build."
  exit 0
fi

echo "Starting Packer build (build_id=${BUILD_ID})..."
"${CMD[@]}"
RC=$?

if [ $RC -ne 0 ]; then
  echo "Packer build failed with exit code $RC" >&2
  exit $RC
fi

echo "Packer build completed. Check output above for AMI IDs and artifact details." 
echo "Next: launch staging instances from the created AMI and validate the 'ollama' systemd service." 
