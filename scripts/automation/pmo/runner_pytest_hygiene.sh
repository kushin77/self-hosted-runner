#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOG_DIR="${REPO_ROOT}/scripts/pmo/logs"
mkdir -p "${LOG_DIR}"

THRESHOLD_SECONDS="${PYTEST_STALE_THRESHOLD_SECONDS:-7200}"
MODE="report"
STRICT=false
JSON=false
ALERT_ISSUE=false
REPO="${REPO:-kushin77/ElevatedIQ-Mono-Repo}"
ISSUE_DEDUP_FILE="${LOG_DIR}/runner_pytest_hygiene_issue_state"

usage() {
  cat <<'EOF'
Usage: runner_pytest_hygiene.sh [options]

Options:
  --threshold-seconds <n>  Stale process threshold (default: 7200)
  --report                 Report stale pytest processes (default)
  --cleanup                Terminate stale pytest processes (TERM then KILL)
  --strict                 Exit non-zero if stale pytest processes exist after run
  --json                   Emit machine-readable JSON summary
  --alert-issue            Create/update GitHub issue when stale processes are found
  -h, --help               Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold-seconds)
      THRESHOLD_SECONDS="$2"
      shift 2
      ;;
    --report)
      MODE="report"
      shift
      ;;
    --cleanup)
      MODE="cleanup"
      shift
      ;;
    --strict)
      STRICT=true
      shift
      ;;
    --json)
      JSON=true
      shift
      ;;
    --alert-issue)
      ALERT_ISSUE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

collect_stale() {
  ps -eo pid=,etimes=,args= \
    | awk -v thr="$THRESHOLD_SECONDS" '
      {
        pid=$1; et=$2;
        $1=""; $2="";
        cmd=substr($0,3);
        if (et >= thr && (cmd ~ /(^|[[:space:]])pytest([[:space:]]|$)/ || cmd ~ /python[0-9.]*[[:space:]]+-m[[:space:]]+pytest/)) {
          print pid "|" et "|" cmd;
        }
      }
    '
}

post_issue_alert() {
  local stale_count="$1"
  local payload="$2"

  if [[ "$ALERT_ISSUE" != "true" ]]; then
    return 0
  fi
  if ! command -v gh >/dev/null 2>&1; then
    return 0
  fi
  if ! gh auth status >/dev/null 2>&1; then
    return 0
  fi

  local sig
  sig="$(printf '%s' "${stale_count}|${payload}" | sha256sum | awk '{print $1}')"
  local prev=""
  if [[ -f "$ISSUE_DEDUP_FILE" ]]; then
    prev="$(cat "$ISSUE_DEDUP_FILE" 2>/dev/null || true)"
  fi
  if [[ "$sig" == "$prev" ]]; then
    return 0
  fi

  local title="[ops][ci] Runner stale pytest watchdog detected orphan processes"
  local body
  body=$(cat <<EOF
Runner watchdog found stale pytest process(es) older than ${THRESHOLD_SECONDS}s.

- Timestamp: $(ts)
- Host: $(hostname -f 2>/dev/null || hostname)
- Stale count: ${stale_count}

Process snapshot:
\
${payload}

NIST: SI-4, CM-3, AU-2
EOF
)

  local existing
  existing="$(gh issue list --repo "$REPO" --state open --search "in:title Runner stale pytest watchdog detected orphan processes" --json number --jq '.[0].number' 2>/dev/null || true)"
  if [[ -n "$existing" && "$existing" != "null" ]]; then
    gh issue comment "$existing" --repo "$REPO" --body "$body" >/dev/null || true
  else
    gh issue create --repo "$REPO" --title "$title" --label "infrastructure,ci,priority-p1" --body "$body" >/dev/null || true
  fi

  printf '%s' "$sig" > "$ISSUE_DEDUP_FILE"
}

STALE_LINES="$(collect_stale || true)"
STALE_COUNT=0
if [[ -n "$STALE_LINES" ]]; then
  STALE_COUNT=$(printf '%s\n' "$STALE_LINES" | sed '/^$/d' | wc -l | tr -d ' ')
fi

KILLED_COUNT=0
if [[ "$MODE" == "cleanup" && "$STALE_COUNT" -gt 0 ]]; then
  while IFS='|' read -r pid etimes cmd; do
    [[ -z "${pid:-}" ]] && continue
    if kill -0 "$pid" 2>/dev/null; then
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done <<< "$STALE_LINES"

  sleep 5

  while IFS='|' read -r pid etimes cmd; do
    [[ -z "${pid:-}" ]] && continue
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done <<< "$STALE_LINES"

  REMAINING="$(collect_stale || true)"
  REMAINING_COUNT=0
  if [[ -n "$REMAINING" ]]; then
    REMAINING_COUNT=$(printf '%s\n' "$REMAINING" | sed '/^$/d' | wc -l | tr -d ' ')
  fi
  KILLED_COUNT=$(( STALE_COUNT - REMAINING_COUNT ))
  STALE_LINES="$REMAINING"
  STALE_COUNT="$REMAINING_COUNT"
fi

HOST_VALUE="$(hostname -f 2>/dev/null || hostname)"
if [[ "$JSON" == "true" ]]; then
  python3 - <<PY
import json
raw = """${STALE_LINES}""".strip()
rows = []
for line in raw.splitlines():
    if not line.strip():
        continue
    pid, et, cmd = line.split("|", 2)
    rows.append({"pid": int(pid), "etimes": int(et), "cmd": cmd})
print(json.dumps({
    "timestamp": "$(ts)",
    "host": "${HOST_VALUE}",
    "mode": "${MODE}",
    "threshold_seconds": int(${THRESHOLD_SECONDS}),
    "stale_count": int(${STALE_COUNT}),
    "killed_count": int(${KILLED_COUNT}),
    "stale_processes": rows,
}, indent=2))
PY
else
  echo "[runner-pytest-hygiene] timestamp=$(ts) host=${HOST_VALUE} mode=${MODE} threshold_seconds=${THRESHOLD_SECONDS} stale_count=${STALE_COUNT} killed_count=${KILLED_COUNT}"
  if [[ -n "$STALE_LINES" ]]; then
    echo "$STALE_LINES" | while IFS='|' read -r pid etimes cmd; do
      [[ -z "${pid:-}" ]] && continue
      echo "- pid=${pid} etimes=${etimes}s cmd=${cmd}"
    done
  fi
fi

if [[ "$STALE_COUNT" -gt 0 ]]; then
  post_issue_alert "$STALE_COUNT" "$STALE_LINES"
fi

if [[ "$STRICT" == "true" && "$STALE_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
