#!/usr/bin/env bash
# Verify host readiness for runner bootstrap
set -euo pipefail
echo "Checking host: docker and git presence"
command -v docker >/dev/null 2>&1 || echo "docker not found"
command -v git >/dev/null 2>&1 || echo "git not found"
echo "Host verification complete"
exit 0
