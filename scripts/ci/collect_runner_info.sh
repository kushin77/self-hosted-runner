#!/usr/bin/env bash
set -euo pipefail
OUTDIR=${1:-./runner-diagnostics}
mkdir -p "$OUTDIR"
echo "Collecting info..."
gitlab-runner --version 2>&1 | tee "$OUTDIR/runner-version.txt" || echo "gitlab-runner not found"
if [ -f /etc/gitlab-runner/config.toml ]; then
  cat /etc/gitlab-runner/config.toml | sed 's/token = ".*"/token = "[REDACTED]"/' > "$OUTDIR/config.toml"
fi
uname -a > "$OUTDIR/uname.txt"
docker info > "$OUTDIR/docker-info.txt" 2>&1 || true
echo "Done"
