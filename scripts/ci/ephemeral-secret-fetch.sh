#!/usr/bin/env bash
set -euo pipefail
# Wrapper helper used in CI to produce environment exports from the repo helper.
# Usage: ./scripts/ci/ephemeral-secret-fetch.sh --provider=vault --secret-path=secret/data/ci/registry

while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider=*) PROVIDER="${1#*=}"; shift ;;
    --secret-path=*) SECRET_PATH="${1#*=}"; shift ;;
    --output-env) OUTPUT_ENV=1; shift ;;
    *) shift ;;
  esac
done

PROVIDER=${PROVIDER:-vault}
SECRET_PATH=${SECRET_PATH:-}

if [[ -z "$SECRET_PATH" ]]; then
  echo "secret path required" >&2
  exit 2
fi

mkdir -p /tmp
./scripts/oidc/get-ephemeral-cred.sh --provider="$PROVIDER" --secret-path="$SECRET_PATH" --output-json > /tmp/ephemeral.json

if [[ ${OUTPUT_ENV:-0} -eq 1 ]]; then
  jq -r 'to_entries|map("export "+(.key|ascii_upcase)+"=\""+.value+"\"")|.[]' /tmp/ephemeral.json
else
  cat /tmp/ephemeral.json
fi
