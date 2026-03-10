#!/usr/bin/env bash
set -euo pipefail

# Auto-verify Issue #2311: look for pasted go-live finalization logs,
# archive them, compute SHA256, append audit entry, and close the issue
# when heuristics indicate success.

REPO="kushin77/self-hosted-runner"
ISSUE=2311
OUT_DIR="artifacts-archive/system-install"
AUDIT_FILE="logs/deployment/audit.jsonl"

mkdir -p "${OUT_DIR}"

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN not set; exiting" >&2
  exit 2
fi

comments_json=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${REPO}/issues/${ISSUE}/comments")

candidate_body=$(echo "$comments_json" | jq -r '.[] | .body' | awk 'length($0) > 200' | tac | sed -n '1p')

if [[ -z "$candidate_body" || "$candidate_body" == "null" ]]; then
  echo "No large comment found to verify." >&2
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
outfile="${OUT_DIR}/go-live-finalize-${timestamp}.log"
echo "$candidate_body" > "$outfile"

sha="$(sha256sum "$outfile" | awk '{print $1}')"

# Append audit entry
mkdir -p "$(dirname "$AUDIT_FILE")"
jq -n --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg actor "automation" \
  --arg action "cloud-finalize" \
  --arg path "$outfile" \
  --arg sha "$sha" \
  '{timestamp:$t,actor:$actor,action:$action,path:$path,sha256:$sha}' >> "$AUDIT_FILE"

# Heuristic: success if log contains any of these phrases
if echo "$candidate_body" | grep -iE "apply complete|terraform applied|deployment complete|service started|started" >/dev/null; then
  # Post success comment with sha and close the issue
  success_comment=$(cat <<EOF
Automated verifier: detected successful cloud finalization.

Archived log: ${outfile}
SHA256: ${sha}

Closing Issue ${ISSUE}.
EOF
)
  curl -s -X POST -H "Authorization: token ${GITHUB_TOKEN}" -d $(jq -Rn --arg b "$success_comment" '{body:$b}') "https://api.github.com/repos/${REPO}/issues/${ISSUE}/comments" >/dev/null
  # Close issue
  curl -s -X PATCH -H "Authorization: token ${GITHUB_TOKEN}" -d '{"state":"closed"}' "https://api.github.com/repos/${REPO}/issues/${ISSUE}" >/dev/null
  echo "Verified and closed issue ${ISSUE}. SHA: ${sha}"
  exit 0
else
  fail_comment=$(cat <<EOF
Automated verifier: log archived (${outfile}) but heuristics did not find expected success markers.

SHA256: ${sha}

Please review the pasted log and re-run the finalize script if needed.
EOF
)
  curl -s -X POST -H "Authorization: token ${GITHUB_TOKEN}" -d $(jq -Rn --arg b "$fail_comment" '{body:$b}') "https://api.github.com/repos/${REPO}/issues/${ISSUE}/comments" >/dev/null
  echo "Archived log but did not auto-close (no success markers). SHA: ${sha}"
  exit 0
fi
