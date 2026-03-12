#!/usr/bin/env bash
set -euo pipefail

# Lightweight secret scanner using git grep for common patterns.
# This is a heuristic tool to surface likely secrets; review findings manually.
# Usage: ./scripts/ops/scan-secrets.sh > secret-scan-report.txt

OUT=secret-scan-report-$(date -u +%Y%m%d_%H%M%SZ).txt
echo "Secret scan report generated at: $(date -u)" > "$OUT"

echo "Scanning for private key markers..." | tee -a "$OUT"
grep -InR --line-number -E "BEGIN( RSA| OPENSSH| DSA| EC) PRIVATE KEY|PRIVATE KEY-----" || true | tee -a "$OUT"

echo "\nScanning for AWS-like access keys..." | tee -a "$OUT"
git grep -InE "AKIA[0-9A-Z]{16}" || true | tee -a "$OUT"

echo "\nScanning for common secret words in config files..." | tee -a "$OUT"
git grep -InE "(aws_secret|aws_secret_access_key|secret_key|SECRET_KEY|GITHUB_TOKEN|github_token|private_key|client_secret|password|passwd)" || true | tee -a "$OUT"

echo "\nScanning for PEM-like files in repo (by name)..." | tee -a "$OUT"
find . -type f -name "*.pem" -o -name "*.key" -o -name "id_rsa" -o -name "id_ed25519" 2>/dev/null | tee -a "$OUT" || true

# If gitleaks installed, run it
if command -v gitleaks >/dev/null 2>&1; then
  echo "\nRunning gitleaks (if available)" | tee -a "$OUT"
  gitleaks detect --source . --report-format json --report-path "gitleaks-report-$(date -u +%Y%m%d_%H%M%SZ).json" || true
  echo "gitleaks output saved (if any)." | tee -a "$OUT"
fi

echo "\nScan complete. Review $OUT for findings." | tee -a "$OUT"

# Print short summary
echo "\nSummary (grep for '::' to find matches):" | tee -a "$OUT"
wc -l "$OUT" | tee -a "$OUT"

echo "Report: $OUT"