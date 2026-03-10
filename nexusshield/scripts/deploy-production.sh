#!/usr/bin/env bash
set -euo pipefail

# Bridge script called by scripts/direct-deploy.sh
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
"$REPO_ROOT/scripts/direct-deploy-production.sh" "$@"
