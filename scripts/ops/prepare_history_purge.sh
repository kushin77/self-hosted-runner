#!/usr/bin/env bash
set -euo pipefail

echo "Prepare history purge: this script will create a mirror bundle and print recommended git-filter-repo command. IT WILL NOT RUN git-filter-repo or force-push."

if [ -z "${1-}" ]; then
  echo "Usage: $0 /path/to/secure-workdir"
  exit 2
fi

WORKDIR="$1"
mkdir -p "$WORKDIR"
echo "Creating mirror clone in $WORKDIR/repo.git"
git clone --mirror "$(git config --get remote.origin.url)" "$WORKDIR/repo.git"
pushd "$WORKDIR/repo.git" >/dev/null
echo "Creating backup bundle ../backup-repo.bundle"
git bundle create ../backup-repo.bundle --all
popd >/dev/null

echo
echo "Identify sensitive paths from: $(pwd)/reports/secret-scan-report-redacted.json"
echo "Then run the following on a secure host (example):"
echo
echo "git filter-repo --invert-paths --paths artifacts/discovery/sa_keys.json \\\n+  --paths nexusshield/infrastructure/terraform/production/terraform-apply-production-20260310-031213.log \\\n+  --paths artifacts/audit/credential-rotation-20260311.jsonl --force"

echo
echo "After filter-repo: run gitleaks in the mirror repo to confirm no findings, then force-push as documented in HISTORY_PURGE_RUNBOOK.md"
