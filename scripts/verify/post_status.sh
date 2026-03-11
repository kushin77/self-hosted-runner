#!/usr/bin/env bash
set -euo pipefail

# Posts a brief status comment to issue #2516 with artifact links and health summary.
REPO=${REPO:-kushin77/self-hosted-runner}
ISSUE=${ISSUE:-2516}

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ART_DIR="artifacts"

# Count artifacts
TF_COUNT=$(ls -1 ${ART_DIR}/terraform 2>/dev/null | wc -l || true)
HEALTH_COUNT=$(ls -1 ${ART_DIR}/local_secrets_health 2>/dev/null | wc -l || true)
AUDIT_COUNT=$(ls -1 ${ART_DIR}/secret_mirror 2>/dev/null | wc -l || true)
VERIFY_COUNT=$(ls -1 ${ART_DIR}/verify 2>/dev/null | wc -l || true)

BODY="Operator status report ($TS)

- Terraform artifacts: ${TF_COUNT}
- Health-check logs: ${HEALTH_COUNT}
- Audit entries: ${AUDIT_COUNT}
- Verification artifacts: ${VERIFY_COUNT}

Artifacts location in repo: artifacts/ (see repo)

No further action required. Automation is running hourly smoke checks."

gh issue comment --repo "$REPO" "$ISSUE" --body "$BODY" || {
  echo "gh comment failed; printing body:";
  echo "$BODY";
}
