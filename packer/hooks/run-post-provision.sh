#!/usr/bin/env bash
set -euo pipefail
# Helper to run repository post-provision smoke checks after image build or host provisioning.
# Usage: packer/CI pipelines should run this script with an inventory that targets newly provisioned hosts.

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$REPO_ROOT"
if [ ! -x ansible/hooks/run-post-provision.sh ]; then
  echo "ansible/hooks/run-post-provision.sh not found or not executable"
  exit 2
fi
ansible/hooks/run-post-provision.sh "$@"
