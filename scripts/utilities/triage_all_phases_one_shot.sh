#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="$REPO_ROOT/logs"
OUT_MD="$OUT_DIR/phase-triage-one-shot-${TS}.md"
OUT_JSON="$OUT_DIR/phase-triage-one-shot-${TS}.json"
LATEST_MD="$OUT_DIR/phase-triage-one-shot-latest.md"
LATEST_JSON="$OUT_DIR/phase-triage-one-shot-latest.json"

mkdir -p "$OUT_DIR"

has_file() {
  [ -f "$1" ] && echo true || echo false
}

has_dir() {
  [ -d "$1" ] && echo true || echo false
}

safe_count_cmd() {
  local cmd="$1"
  set +e
  local out
  out="$(eval "$cmd" 2>/dev/null)"
  local rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "-1"
    return 0
  fi
  if [ -z "$out" ]; then
    echo "0"
  else
    printf "%s\n" "$out" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
  fi
}

set +e
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
CLUSTERS_RAW="$(gcloud container clusters list --project="${PROJECT_ID}" --format='value(name)' 2>/dev/null)"
CLUSTERS_RC=$?
COMPUTE_COUNT="$(safe_count_cmd "gcloud compute instances list --project='${PROJECT_ID}' --format='value(name)'")"
SQL_COUNT="$(safe_count_cmd "gcloud sql instances list --project='${PROJECT_ID}' --format='value(name)'")"
TRIAGE_TIMER_STATE="$(systemctl is-active monitoring-alert-triage.timer 2>/dev/null)"
TRIAGE_STATUS_STATE="unknown"
TRIAGE_STATUS_MSG="status file not found"
if [ -f "$REPO_ROOT/logs/monitoring-alert-issue-triage.status" ]; then
  TRIAGE_STATUS_STATE="$(sed -n 's/^state=//p' "$REPO_ROOT/logs/monitoring-alert-issue-triage.status" | head -1)"
  TRIAGE_STATUS_MSG="$(sed -n 's/^message=//p' "$REPO_ROOT/logs/monitoring-alert-issue-triage.status" | head -1)"
fi
set -e

if [ "$CLUSTERS_RC" -eq 0 ]; then
  CLUSTER_COUNT="$(printf "%s\n" "$CLUSTERS_RAW" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
else
  CLUSTER_COUNT="-1"
fi

PHASE0_STATUS="COMPLETE"
PHASE0_REASON="terraform/phase0-core present"
if [ "$(has_dir terraform/phase0-core)" != "true" ]; then
  PHASE0_STATUS="BLOCKED"
  PHASE0_REASON="terraform/phase0-core missing"
fi

PHASE1_STATUS="COMPLETE"
PHASE1_REASON="terraform/phase1-core and kubernetes manifest present"
if [ "$(has_dir terraform/phase1-core)" != "true" ] || [ "$(has_file kubernetes/phase1-deployment.yaml)" != "true" ]; then
  PHASE1_STATUS="BLOCKED"
  PHASE1_REASON="phase1 artifacts missing"
elif [ "$CLUSTER_COUNT" = "0" ]; then
  PHASE1_STATUS="BLOCKED"
  PHASE1_REASON="no active GKE clusters found"
fi

PHASE2_STATUS="COMPLETE"
PHASE2_REASON="terraform/phase2.plan present"
if [ "$(has_file terraform/phase2.plan)" != "true" ]; then
  PHASE2_STATUS="BLOCKED"
  PHASE2_REASON="terraform/phase2.plan missing"
fi

PHASE3_STATUS="COMPLETE"
PHASE3_REASON="phase3 credential scripts present"
if [ "$(has_file scripts/phase3b-credentials-aws-vault.sh)" != "true" ]; then
  PHASE3_STATUS="BLOCKED"
  PHASE3_REASON="scripts/phase3b-credentials-aws-vault.sh missing"
fi

PHASE4_STATUS="COMPLETE"
PHASE4_REASON="phase4 finalization script present"
if [ "$(has_file scripts/utilities/final-system-completion.sh)" != "true" ]; then
  PHASE4_STATUS="BLOCKED"
  PHASE4_REASON="scripts/utilities/final-system-completion.sh missing"
fi

PHASE5_STATUS="COMPLETE"
PHASE5_REASON="phase5 automation script present"
if [ "$(has_file scripts/automation/phase5-complete-automation-enhanced.sh)" != "true" ] && [ "$(has_file scripts/automation/phase5-complete-automation.sh)" != "true" ]; then
  PHASE5_STATUS="BLOCKED"
  PHASE5_REASON="phase5 automation scripts missing"
fi

PHASE6_STATUS="COMPLETE"
PHASE6_REASON="phase6 automation script present"
if [ "$(has_file scripts/phase6-autonomous-deploy.sh)" != "true" ] && [ "$(has_file scripts/automation/phase6-quickstart.sh)" != "true" ]; then
  PHASE6_STATUS="BLOCKED"
  PHASE6_REASON="phase6 automation scripts missing"
fi

MON_STATUS="COMPLETE"
MON_REASON="triage timer active and status ok"
if [ "$TRIAGE_TIMER_STATE" != "active" ]; then
  MON_STATUS="BLOCKED"
  MON_REASON="monitoring-alert-triage.timer is ${TRIAGE_TIMER_STATE:-unknown}"
elif [ "$TRIAGE_STATUS_STATE" != "ok" ]; then
  MON_STATUS="BLOCKED"
  MON_REASON="$TRIAGE_STATUS_MSG"
fi

cat > "$OUT_MD" <<EOF
# One-Shot Phase Triage Report

- Timestamp (UTC): ${TS}
- Project: ${PROJECT_ID:-unknown}
- Active account: ${ACTIVE_ACCOUNT:-unknown}
- Git revision: $(git rev-parse --short HEAD)

## Runtime Snapshot

- GKE clusters discovered: ${CLUSTER_COUNT}
- Compute instances discovered: ${COMPUTE_COUNT}
- Cloud SQL instances discovered: ${SQL_COUNT}
- Triage timer state: ${TRIAGE_TIMER_STATE:-unknown}
- Triage status state: ${TRIAGE_STATUS_STATE}
- Triage status message: ${TRIAGE_STATUS_MSG}

## Phase Matrix

| Phase | Status | Reason |
|---|---|---|
| Phase 0 | ${PHASE0_STATUS} | ${PHASE0_REASON} |
| Phase 1 | ${PHASE1_STATUS} | ${PHASE1_REASON} |
| Phase 2 | ${PHASE2_STATUS} | ${PHASE2_REASON} |
| Phase 3 | ${PHASE3_STATUS} | ${PHASE3_REASON} |
| Phase 4 | ${PHASE4_STATUS} | ${PHASE4_REASON} |
| Phase 5 | ${PHASE5_STATUS} | ${PHASE5_REASON} |
| Phase 6 | ${PHASE6_STATUS} | ${PHASE6_REASON} |
| Monitoring Triage | ${MON_STATUS} | ${MON_REASON} |

## Recommended Immediate Actions

1. If Phase 1 is blocked, restore or create a reachable cluster and monitoring endpoints.
2. Configure endpoint URLs directly or via GSM endpoint secrets for triage service.
3. Re-run this script after remediation to confirm all statuses become COMPLETE.
EOF

cat > "$OUT_JSON" <<EOF
{
  "timestamp_utc": "${TS}",
  "project_id": "${PROJECT_ID}",
  "active_account": "${ACTIVE_ACCOUNT}",
  "git_revision": "$(git rev-parse --short HEAD)",
  "runtime": {
    "gke_clusters": "${CLUSTER_COUNT}",
    "compute_instances": "${COMPUTE_COUNT}",
    "cloud_sql_instances": "${SQL_COUNT}",
    "triage_timer_state": "${TRIAGE_TIMER_STATE}",
    "triage_status_state": "${TRIAGE_STATUS_STATE}",
    "triage_status_message": "${TRIAGE_STATUS_MSG//\"/\\\"}"
  },
  "phases": {
    "phase0": {"status": "${PHASE0_STATUS}", "reason": "${PHASE0_REASON}"},
    "phase1": {"status": "${PHASE1_STATUS}", "reason": "${PHASE1_REASON}"},
    "phase2": {"status": "${PHASE2_STATUS}", "reason": "${PHASE2_REASON}"},
    "phase3": {"status": "${PHASE3_STATUS}", "reason": "${PHASE3_REASON}"},
    "phase4": {"status": "${PHASE4_STATUS}", "reason": "${PHASE4_REASON}"},
    "phase5": {"status": "${PHASE5_STATUS}", "reason": "${PHASE5_REASON}"},
    "phase6": {"status": "${PHASE6_STATUS}", "reason": "${PHASE6_REASON}"},
    "monitoring_triage": {"status": "${MON_STATUS}", "reason": "${MON_REASON//\"/\\\"}"}
  }
}
EOF

cp "$OUT_MD" "$LATEST_MD"
cp "$OUT_JSON" "$LATEST_JSON"

echo "Generated: $OUT_MD"
echo "Generated: $OUT_JSON"
echo "Updated: $LATEST_MD"
echo "Updated: $LATEST_JSON"
