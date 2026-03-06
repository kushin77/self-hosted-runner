#!/usr/bin/env bash
set -euo pipefail

usage() { cat <<EOF
Usage: $0 [--gh-repo owner/repo] [--local]

Checks required secrets either via `gh secret list` for a remote repo or by
ensuring specific env vars are set locally.
EOF
}

GH_REPO=""
LOCAL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gh-repo) GH_REPO="$2"; shift 2;;
    --local) LOCAL=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

required=(
  VAULT_ROLE_ID
  VAULT_SECRET_ID
  MINIO_ACCESS_KEY
  MINIO_SECRET_KEY
  TF_VAR_SERVICE_ACCOUNT_KEY
)

if [[ $LOCAL -eq 1 ]]; then
  missing=()
  for k in "${required[@]}"; do
    if [[ -z "${!k:-}" ]]; then
      missing+=("$k")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "All required env vars present locally."; exit 0
  fi
  echo "Missing local env vars: ${missing[*]}"; exit 1
fi

if [[ -n "$GH_REPO" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI not found. Install gh and authenticate to continue."; exit 2
  fi
  missing=()
  present=$(gh secret list -R "$GH_REPO" --json name -q '.[].name' 2>/dev/null || true)
  for k in "${required[@]}"; do
    if ! echo "$present" | grep -q "^${k}$"; then
      missing+=("$k")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "All required repo secrets present in $GH_REPO."; exit 0
  fi
  echo "Missing repo secrets in $GH_REPO: ${missing[*]}"; exit 1
fi

echo "Specify --local or --gh-repo owner/repo"; usage; exit 2
