#!/usr/bin/env bash
# Minimal mock of `gcloud secrets versions access latest --secret=NAME --format='get(payload.data)'`
set -euo pipefail

if [[ "$#" -ge 3 && "$1" == "secrets" && "$2" == "versions" && "$3" == "access" ]]; then
  secretName=""
  for a in "$@"; do
    case "$a" in
      --secret=*) secretName="${a#--secret=}" ;;
    esac
  done
  if [[ -z "$secretName" ]]; then
    echo "";
    exit 1
  fi
  payload="mock-payload-for-${secretName}"
  # output base64 encoded payload as real gcloud would
  echo -n "$payload" | base64
  exit 0
fi

# fallback to real gcloud if available
if command -v gcloud >/dev/null 2>&1; then
  exec gcloud "$@"
else
  echo "mock gcloud: unsupported command" >&2
  exit 2
fi
