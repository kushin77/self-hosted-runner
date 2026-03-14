#!/usr/bin/env bash
set -euo pipefail

# Secret scan: prefer gitleaks if available, fallback to simple grep patterns
if command -v gitleaks >/dev/null 2>&1; then
  echo "Running gitleaks..."
  gitleaks detect --source . --report-format json --report-path secret-scan-report.json || {
    echo "Secrets detected. See secret-scan-report.json" >&2
    exit 1
  }
  echo "No secrets detected by gitleaks."
  exit 0
fi

echo "gitleaks not found; performing basic pattern scans..."
patterns=(
  "AWS_SECRET_ACCESS_KEY"
  "AWS_ACCESS_KEY_ID"
  "GITHUB_TOKEN"
  "BEGIN PRIVATE KEY"
  "BEGIN RSA PRIVATE KEY"
  "PRIVATE KEY-----"
)
found=0
for p in "${patterns[@]}"; do
  if git grep -n --no-color -I "$p" >/dev/null 2>&1; then
    echo "Found pattern: $p"
    git grep -n --no-color -I "$p" || true
    found=1
  fi
done

if [ "$found" -eq 1 ]; then
  echo "Potential secrets found (grep). Review required." >&2
  exit 1
fi

echo "No obvious secrets detected by basic scans."
exit 0
