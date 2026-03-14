#!/usr/bin/env bash
set -euo pipefail

# Triage active monitoring alerts into GitHub issues.
# Idempotent behavior:
# - Create issue for new firing alerts
# - Reuse existing issue for known firing alerts
# - Close issue when alert is no longer firing
#
# Required:
#   GITHUB_REPOSITORY=owner/repo
#   GITHUB_TOKEN (or GITHUB_TOKEN_GSM_SECRET with gcloud auth)
#
# Optional:
#   PROM_URL=http://prometheus:9090
#   AM_URL=http://alertmanager:9093
#   TRIAGE_LABEL=monitoring-triage
#   TRIAGE_EXTRA_LABELS=incident,automated
#   TRIAGE_DRY_RUN=true

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT_LOG="${REPO_ROOT}/logs/monitoring-alert-issue-triage.jsonl"
mkdir -p "$(dirname "$AUDIT_LOG")"

PROM_URL="${PROM_URL:-}"
AM_URL="${AM_URL:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GITHUB_API_BASE="${GITHUB_API_BASE:-https://api.github.com}"
TRIAGE_LABEL="${TRIAGE_LABEL:-monitoring-triage}"
TRIAGE_EXTRA_LABELS="${TRIAGE_EXTRA_LABELS:-incident,automated}"
TRIAGE_DRY_RUN="${TRIAGE_DRY_RUN:-false}"

log_event() {
  local event="$1"
  local details="${2:-}"
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"${event}\",\"details\":\"${details//\"/\\\"}\"}" >> "$AUDIT_LOG"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

resolve_github_token() {
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    return 0
  fi

  if [ -n "${GITHUB_TOKEN_GSM_SECRET:-}" ] && command -v gcloud >/dev/null 2>&1; then
    local project="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
    if [ -n "$project" ]; then
      GITHUB_TOKEN="$(gcloud secrets versions access latest --secret="$GITHUB_TOKEN_GSM_SECRET" --project="$project" 2>/dev/null || true)"
      export GITHUB_TOKEN
    fi
  fi

  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "GITHUB_TOKEN is required (or set GITHUB_TOKEN_GSM_SECRET + gcloud auth)." >&2
    exit 2
  fi
}

gh_api() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"

  if [ "$TRIAGE_DRY_RUN" = "true" ]; then
    echo "{\"dryRun\":true,\"method\":\"$method\",\"path\":\"$path\"}"
    return 0
  fi

  if [ -n "$payload" ]; then
    curl -fsS -X "$method" \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "Content-Type: application/json" \
      "${GITHUB_API_BASE}${path}" \
      -d "$payload"
  else
    curl -fsS -X "$method" \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "${GITHUB_API_BASE}${path}"
  fi
}

fetch_prometheus_alerts() {
  if [ -z "$PROM_URL" ]; then
    echo '[]'
    return 0
  fi

  curl -fsS "$PROM_URL/api/v1/alerts" | jq -c '
    (.data.alerts // [])
    | map(select((.state // "") == "firing"))
    | map({
        source: "prometheus",
        startsAt: (.activeAt // ""),
        labels: (.labels // {}),
        annotations: (.annotations // {})
      })
  '
}

fetch_alertmanager_alerts() {
  if [ -z "$AM_URL" ]; then
    echo '[]'
    return 0
  fi

  curl -fsS "$AM_URL/api/v2/alerts" | jq -c '
    map(select((.status.state // "") == "active"))
    | map({
        source: "alertmanager",
        startsAt: (.startsAt // ""),
        labels: (.labels // {}),
        annotations: (.annotations // {})
      })
  '
}

severity_label() {
  local sev="$1"
  case "${sev,,}" in
    critical) echo "severity/critical" ;;
    warning) echo "severity/warning" ;;
    info) echo "severity/info" ;;
    *) echo "severity/unknown" ;;
  esac
}

fingerprint_for_alert() {
  local alert_json="$1"
  local key
  key="$(echo "$alert_json" | jq -r '[
      .labels.alertname // "unknown",
      .labels.severity // "unknown",
      .labels.instance // "",
      .labels.job // "",
      .labels.service // "",
      .labels.namespace // "",
      .labels.cluster // ""
    ] | join("|")')"
  printf "%s" "$key" | sha1sum | awk '{print $1}'
}

search_open_issue_by_fp() {
  local short_fp="$1"
  local q
  q="repo:${GITHUB_REPOSITORY} is:issue is:open in:title mon-triage:${short_fp}"
  local encoded
  encoded="$(urlencode "$q")"
  gh_api GET "/search/issues?q=${encoded}" | jq -r '.items[0].number // empty'
}

create_issue_for_alert() {
  local alert_json="$1"
  local fp="$2"
  local short_fp="${fp:0:12}"

  local alertname severity source starts_at summary description sev_label labels_json annotations_json title body payload
  alertname="$(echo "$alert_json" | jq -r '.labels.alertname // "UnknownAlert"')"
  severity="$(echo "$alert_json" | jq -r '.labels.severity // "unknown"')"
  source="$(echo "$alert_json" | jq -r '.source')"
  starts_at="$(echo "$alert_json" | jq -r '.startsAt // ""')"
  summary="$(echo "$alert_json" | jq -r '.annotations.summary // "No summary provided"')"
  description="$(echo "$alert_json" | jq -r '.annotations.description // "No description provided"')"
  labels_json="$(echo "$alert_json" | jq -c '.labels')"
  annotations_json="$(echo "$alert_json" | jq -c '.annotations')"
  sev_label="$(severity_label "$severity")"

  title="[MONITORING][${severity^^}][mon-triage:${short_fp}] ${alertname}"
  body=$(cat <<EOF
Automated monitoring triage issue.

mon-triage-id: ${fp}
alertname: ${alertname}
severity: ${severity}
source: ${source}
startsAt: ${starts_at}

summary: ${summary}

description: ${description}

labels-json:
\`\`\`json
${labels_json}
\`\`\`

annotations-json:
\`\`\`json
${annotations_json}
\`\`\`
EOF
)

  payload=$(jq -n \
    --arg t "$title" \
    --arg b "$body" \
    --arg triage "$TRIAGE_LABEL" \
    --arg extra "$TRIAGE_EXTRA_LABELS" \
    --arg sev "$sev_label" \
    '{title:$t, body:$b, labels: ([$triage,$sev] + ($extra|split(",")|map(select(length>0))))}')

  local issue_number
  issue_number="$(gh_api POST "/repos/${GITHUB_REPOSITORY}/issues" "$payload" | jq -r '.number')"

  log_event "issue_created" "alert=${alertname} fp=${short_fp} issue=${issue_number}"
  echo "$issue_number"
}

close_issue_for_resolved_alert() {
  local issue_number="$1"
  local short_fp="$2"

  local comment_payload patch_payload
  comment_payload=$(jq -n --arg b "Automated resolution: alert is no longer firing. mon-triage:${short_fp}" '{body:$b}')
  patch_payload='{"state":"closed","state_reason":"completed"}'

  gh_api POST "/repos/${GITHUB_REPOSITORY}/issues/${issue_number}/comments" "$comment_payload" >/dev/null
  gh_api PATCH "/repos/${GITHUB_REPOSITORY}/issues/${issue_number}" "$patch_payload" >/dev/null
  log_event "issue_closed" "mon-triage=${short_fp} issue=${issue_number}"
}

main() {
  require_cmd curl
  require_cmd jq
  require_cmd sha1sum

  if [ -z "$GITHUB_REPOSITORY" ]; then
    echo "GITHUB_REPOSITORY is required (owner/repo)." >&2
    exit 2
  fi

  resolve_github_token

  if [ -z "$PROM_URL" ] && [ -z "$AM_URL" ]; then
    echo "Set PROM_URL and/or AM_URL to collect alerts." >&2
    exit 2
  fi

  log_event "triage_start" "repo=${GITHUB_REPOSITORY} prom=${PROM_URL:-none} am=${AM_URL:-none}"

  local prom_alerts am_alerts merged
  prom_alerts="$(fetch_prometheus_alerts)"
  am_alerts="$(fetch_alertmanager_alerts)"
  merged="$(jq -c -n --argjson p "$prom_alerts" --argjson a "$am_alerts" '$p + $a')"

  declare -A ACTIVE_FPS

  while IFS= read -r alert; do
    [ -z "$alert" ] && continue

    local fp short_fp existing issue_number
    fp="$(fingerprint_for_alert "$alert")"
    short_fp="${fp:0:12}"
    ACTIVE_FPS["$fp"]=1

    existing="$(search_open_issue_by_fp "$short_fp")"
    if [ -n "$existing" ]; then
      log_event "issue_exists" "mon-triage=${short_fp} issue=${existing}"
      continue
    fi

    issue_number="$(create_issue_for_alert "$alert" "$fp")"
    log_event "triaged_alert" "mon-triage=${short_fp} issue=${issue_number}"
  done < <(echo "$merged" | jq -c '.[]')

  local open_triage
  open_triage="$(gh_api GET "/repos/${GITHUB_REPOSITORY}/issues?state=open&labels=${TRIAGE_LABEL}&per_page=100")"

  while IFS= read -r item; do
    [ -z "$item" ] && continue

    local issue_number body fp short_fp
    issue_number="$(echo "$item" | jq -r '.number')"
    body="$(echo "$item" | jq -r '.body // ""')"
    fp="$(printf "%s" "$body" | sed -n 's/^mon-triage-id: \([a-f0-9]\{40\}\).*/\1/p' | head -1)"

    if [ -z "$fp" ]; then
      continue
    fi

    if [ -z "${ACTIVE_FPS[$fp]:-}" ]; then
      short_fp="${fp:0:12}"
      close_issue_for_resolved_alert "$issue_number" "$short_fp"
    fi
  done < <(echo "$open_triage" | jq -c '.[]')

  log_event "triage_complete" "active_alerts=$(echo "$merged" | jq 'length')"
  echo "Monitoring triage completed successfully."
}

main "$@"
