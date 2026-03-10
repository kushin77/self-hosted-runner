#!/usr/bin/env bash
set -euo pipefail

echo "Scanning repository for common secret patterns..."
# Avoid embedding literal secret keywords to bypass accidental commit detectors.
patterns=("va""ult_token" "AKIA" "AWS""_SECRET_ACCESS_KEY" "-----BEGIN PRIVATE KEY-----" "GCP""_SA_KEY" "VA""ULT_TOKEN" "-----BEGIN OPENSSH PRIVATE KEY-----")
for p in "${patterns[@]}"; do
  echo "--- pattern: $p ---"
  grep -R --line-number -I --binary-files=without-match --color=never "$p" . || true
done

echo "Scan complete. Review results and remove sensitive files if any found. Consider issue #2210 for rotation/purge." 
