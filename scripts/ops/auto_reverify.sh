#!/usr/bin/env bash
set -euo pipefail
# Automated re-verification helper
# - Attempts to fetch SSH verifier key via fetch_credentials.sh
# - If available, runs `verify_deployment.sh` remotely and collects evidence
# - Optionally uploads artifacts to S3 and posts a GitHub issue comment

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
FETCH_SCRIPT="$ROOT_DIR/scripts/ops/fetch_credentials.sh"
VERIFY_SCRIPT="$ROOT_DIR/scripts/ops/verify_deployment.sh"
UPLOAD_SCRIPT="$ROOT_DIR/scripts/ops/upload_jsonl_to_s3.sh"

usage(){
  cat <<EOF
Usage: $0 --host HOST [--s3-bucket BUCKET] [--github-token TOKEN] [--issue ISSUE] [--dry-run]

Options:
  --host HOST           On-prem host IP or name to verify (required)
  --s3-bucket BUCKET    Optional S3 bucket to upload artifacts
  --github-token TOKEN  Optional GitHub token to post issue comments
  --issue ISSUE         GitHub issue number to comment on (owner assumed)
  --dry-run             Do everything except upload/post comments
EOF
  exit 1
}

HOST=""
S3_BUCKET=""
GITHUB_TOKEN=""
ISSUE_NUMBER=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --s3-bucket) S3_BUCKET="$2"; shift 2;;
    --github-token) GITHUB_TOKEN="$2"; shift 2;;
    --issue) ISSUE_NUMBER="$2"; shift 2;;
    --dry-run) DRY_RUN="true"; shift 1;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "Missing --host" >&2
  usage
fi

echo "[auto_reverify] Starting for host: $HOST"

# Attempt to fetch credentials (this script is designed to be safe to source)
if [[ -x "$FETCH_SCRIPT" ]]; then
  # shellcheck disable=SC1090
  source "$FETCH_SCRIPT" || true
else
  echo "[auto_reverify] fetch script not found: $FETCH_SCRIPT" >&2
fi

if [[ -n "${SSH_KEY_PATH:-}" && -f "${SSH_KEY_PATH}" ]]; then
  echo "[auto_reverify] SSH key available at $SSH_KEY_PATH"
else
  echo "[auto_reverify] SSH key not available; will attempt to run local verifier only"
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="/tmp/autoreverify_$TS"
mkdir -p "$OUT_DIR"

# Run local verifier (will also attempt remote verifier if SSH key present)
VERIFIER_LOG="$OUT_DIR/deployment_verification_${TS}.txt"
echo "[auto_reverify] Running verifier (logs -> $VERIFIER_LOG)"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[auto_reverify] DRY RUN: would run $VERIFY_SCRIPT with ONPREM_HOST=$HOST" | tee "$VERIFIER_LOG"
else
  ONPREM_HOST="$HOST" bash "$VERIFY_SCRIPT" 2>&1 | tee "$VERIFIER_LOG"
fi

# Gather any jsonl report created by verifier or post_deploy script
REPORT_JSONL="$(ls /tmp/post_deploy_validation_*.jsonl 2>/dev/null | tail -n1 || true)"
if [[ -n "$REPORT_JSONL" ]]; then
  cp "$REPORT_JSONL" "$OUT_DIR/" || true
fi

# If S3_BUCKET provided, upload artifacts
if [[ -n "$S3_BUCKET" && "$DRY_RUN" != "true" ]]; then
  if [[ -x "$UPLOAD_SCRIPT" ]]; then
    echo "[auto_reverify] Uploading artifacts to S3 bucket $S3_BUCKET"
    bash "$UPLOAD_SCRIPT" --bucket "$S3_BUCKET" --files "$OUT_DIR"/* || echo "[auto_reverify] Upload failed"
  else
    echo "[auto_reverify] upload script not found: $UPLOAD_SCRIPT"
  fi
fi

# Post comment to GitHub issue if token provided
if [[ -n "$GITHUB_TOKEN" && -n "$ISSUE_NUMBER" && "$DRY_RUN" != "true" ]]; then
  OWNER="kushin77"
  REPO="self-hosted-runner"
  COMMENT_BODY=$(cat <<EOF
Automated re-verification run for host $HOST

Verifier output (first 200 lines):
$(head -n 200 "$VERIFIER_LOG" | sed 's/$/\n/' )

Artifacts: attached on runner at $OUT_DIR
EOF
)
  curl -sS -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/json" \
    "https://api.github.com/repos/${OWNER}/${REPO}/issues/${ISSUE_NUMBER}/comments" \
    -d "$(jq -Rn --arg body "$COMMENT_BODY" '{body:$body}')" || echo "[auto_reverify] failed to post comment"
fi

echo "[auto_reverify] Completed; evidence directory: $OUT_DIR"
exit 0
