#!/usr/bin/env bash
set -euo pipefail

# Reviews overlap in shell automation by finding duplicate script names and
# duplicate content hashes. Produces a markdown report usable in PR review.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT_DIR="${REPO_ROOT}/reports/qa"
LOG_DIR="${REPO_ROOT}/logs/qa"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_FILE="${REPORT_FILE:-${REPORT_DIR}/overlap-review-${TS}.md}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/overlap-review-${TS}.jsonl}"

mkdir -p "$REPORT_DIR" "$LOG_DIR"

json_log() {
  local level="$1"
  local msg="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)" \
      --arg level "$level" \
      --arg msg "$msg" \
      '{timestamp:$ts,level:$level,message:$msg}' >> "$LOG_FILE"
  else
    printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$msg" >> "$LOG_FILE"
  fi
}

mapfile -t shell_scripts < <(find "$REPO_ROOT/scripts" -type f -name '*.sh' | sort)

{
  echo "# Script Overlap Review"
  echo
  echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Scope"
  echo
  echo "- Total shell scripts scanned: ${#shell_scripts[@]}"
  echo
  echo "## Duplicate Basenames"
  echo
} > "$REPORT_FILE"

if [ ${#shell_scripts[@]} -gt 0 ]; then
  basename_report=$(printf '%s\n' "${shell_scripts[@]}" | awk -F/ '{print $NF}' | sort | uniq -cd | sed 's/^ *//')
else
  basename_report=""
fi

if [ -n "$basename_report" ]; then
  echo '```text' >> "$REPORT_FILE"
  echo "$basename_report" >> "$REPORT_FILE"
  echo '```' >> "$REPORT_FILE"
  json_log "WARN" "duplicate basenames detected"
else
  echo "No duplicate basenames found." >> "$REPORT_FILE"
  json_log "INFO" "no duplicate basenames"
fi

echo >> "$REPORT_FILE"
echo "## Duplicate Content Hashes" >> "$REPORT_FILE"
echo >> "$REPORT_FILE"

tmp_hashes=$(mktemp)
for f in "${shell_scripts[@]}"; do
  [ -f "$f" ] || continue
  if command -v sha256sum >/dev/null 2>&1; then
    h=$(sha256sum "$f" | awk '{print $1}')
  else
    h=$(openssl dgst -sha256 "$f" | awk '{print $2}')
  fi
  printf '%s %s\n' "$h" "$f" >> "$tmp_hashes"
done

dup_hashes=$(awk '{print $1}' "$tmp_hashes" | sort | uniq -d)
if [ -n "$dup_hashes" ]; then
  while IFS= read -r h; do
    echo "- Hash ${h}" >> "$REPORT_FILE"
    awk -v hash="$h" '$1==hash {print "  - " $2}' "$tmp_hashes" >> "$REPORT_FILE"
  done <<< "$dup_hashes"
  json_log "WARN" "duplicate script content detected"
else
  echo "No duplicate content hashes found." >> "$REPORT_FILE"
  json_log "INFO" "no duplicate content hashes"
fi

rm -f "$tmp_hashes"

echo >> "$REPORT_FILE"
echo "## Consolidation Suggestions" >> "$REPORT_FILE"
echo >> "$REPORT_FILE"
echo "1. Keep a single authoritative script per operational domain (cleanup, secrets, health, testing)." >> "$REPORT_FILE"
echo "2. Repoint wrappers to canonical scripts instead of copying logic." >> "$REPORT_FILE"
echo "3. Keep dry-run as default for any shutdown or cleanup path." >> "$REPORT_FILE"

echo "Overlap review report: $REPORT_FILE"
