#!/bin/bash
# Secret sprawl detection and scanning script
# This script runs multiple secret detection engines to prevent credential leaks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
REPORT_DIR="${REPO_ROOT}/.security/secret-scan-reports"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Create report directory
mkdir -p "${REPORT_DIR}"

echo "🔍 Starting secret sprawl detection..."
echo "Repository: ${REPO_ROOT}"
echo "Timestamp: ${TIMESTAMP}"
echo ""

# Counter for findings
TOTAL_FINDINGS=0

# 1. Detect-secrets scan
echo "[1/5] Running detect-secrets..."
if command -v detect-secrets &> /dev/null; then
  SECRETS_REPORT="${REPORT_DIR}/detect-secrets-${TIMESTAMP}.json"
  detect-secrets scan \
    --baseline .secrets.baseline \
    --all-files \
    --force-init > "${SECRETS_REPORT}" || true
  
  SECRETS_FINDINGS=$(grep -o '"is_secret": true' "${SECRETS_REPORT}" | wc -l)
  if [ "${SECRETS_FINDINGS}" -gt 0 ]; then
    echo "⚠️  Detect-secrets found ${SECRETS_FINDINGS} potential secrets"
    TOTAL_FINDINGS=$((TOTAL_FINDINGS + SECRETS_FINDINGS))
  else
    echo "✅ Detect-secrets: No secrets found"
  fi
else
  echo "⚠️  detect-secrets not installed, skipping"
fi

# 2. Gitleaks scan
echo "[2/5] Running gitleaks..."
if command -v gitleaks &> /dev/null; then
  GITLEAKS_REPORT="${REPORT_DIR}/gitleaks-${TIMESTAMP}.json"
  gitleaks detect \
    --source local \
    --report-path "${GITLEAKS_REPORT}" \
    --exit-code 0 || true
  
  if [ -f "${GITLEAKS_REPORT}" ]; then
    GITLEAKS_FINDINGS=$(jq -r '.[] | length // 0' "${GITLEAKS_REPORT}" 2>/dev/null || echo 0)
    if [ "${GITLEAKS_FINDINGS}" -gt 0 ]; then
      echo "⚠️  Gitleaks found ${GITLEAKS_FINDINGS} potential secrets"
      TOTAL_FINDINGS=$((TOTAL_FINDINGS + GITLEAKS_FINDINGS))
    fi
  fi
  echo "✅ Gitleaks: Scan complete"
else
  echo "⚠️  gitleaks not installed, skipping"
fi

# 3. Pip-audit for dependencies
echo "[3/5] Running pip-audit..."
if command -v pip-audit &> /dev/null; then
  PIP_AUDIT_REPORT="${REPORT_DIR}/pip-audit-${TIMESTAMP}.json"
  pip-audit \
    --desc \
    --output json \
    --format json > "${PIP_AUDIT_REPORT}" || true
  
  PIP_FINDINGS=$(jq -r '.vulnerabilities | length' "${PIP_AUDIT_REPORT}" 2>/dev/null || echo 0)
  if [ "${PIP_FINDINGS}" -gt 0 ]; then
    echo "⚠️  pip-audit found ${PIP_FINDINGS} vulnerabilities"
    TOTAL_FINDINGS=$((TOTAL_FINDINGS + PIP_FINDINGS))
  else
    echo "✅ pip-audit: No vulnerabilities found"
  fi
else
  echo "⚠️  pip-audit not installed, skipping"
fi

# 4. Bandit for Python security
echo "[4/5] Running bandit..."
if command -v bandit &> /dev/null; then
  BANDIT_REPORT="${REPORT_DIR}/bandit-${TIMESTAMP}.json"
  bandit -r backend/ \
    --format json \
    -o "${BANDIT_REPORT}" \
    --exit-code 0 || true
  
  BANDIT_FINDINGS=$(jq -r '.metrics."_totals".HIGH // 0' "${BANDIT_REPORT}")
  if [ "${BANDIT_FINDINGS}" -gt 0 ]; then
    echo "⚠️  Bandit found ${BANDIT_FINDINGS} high-severity issues"
    TOTAL_FINDINGS=$((TOTAL_FINDINGS + BANDIT_FINDINGS))
  else
    echo "✅ Bandit: No high-severity issues found"
  fi
else
  echo "⚠️  bandit not installed, skipping"
fi

# 5. Check for hardcoded credentials in common patterns
echo "[5/5] Checking for hardcoded credential patterns..."
PATTERN_FINDINGS=0
PATTERNS=(
  "password['\"]\\s*[:=]\\s*['\"][^'\"]*['\"]"
  "api[_-]?key['\"]\\s*[:=]\\s*['\"][^'\"]*['\"]"
  "secret['\"]\\s*[:=]\\s*['\"][^'\"]*['\"]"
  "token['\"]\\s*[:=]\\s*['\"][^'\"]*['\"]"
  "credentials['\"]\\s*[:=]\\s*['\"][^'\"]*['\"]"
)

for pattern in "${PATTERNS[@]}"; do
  matches=$(grep -r -E "${pattern}" \
    --exclude-dir=.git \
    --exclude-dir=node_modules \
    --exclude-dir=.venv \
    --exclude='*.log' \
    --exclude='.secrets*' \
    --exclude='*.baseline' \
    "${REPO_ROOT}" 2>/dev/null || true)
  
  if [ -n "${matches}" ]; then
    PATTERN_FINDINGS=$((PATTERN_FINDINGS + $(echo "${matches}" | wc -l)))
  fi
done

if [ "${PATTERN_FINDINGS}" -gt 0 ]; then
  echo "⚠️  Found ${PATTERN_FINDINGS} hardcoded credential patterns"
  TOTAL_FINDINGS=$((TOTAL_FINDINGS + PATTERN_FINDINGS))
else
  echo "✅ No hardcoded credential patterns found"
fi

# Summary report
echo ""
echo "════════════════════════════════════════════════════"
echo "SECRET SPRAWL DETECTION SUMMARY"
echo "════════════════════════════════════════════════════"
echo "Timestamp: ${TIMESTAMP}"
echo "Repository: ${REPO_ROOT}"
echo "Report Location: ${REPORT_DIR}"
echo "Total Findings: ${TOTAL_FINDINGS}"
echo ""

# Create summary JSON
SUMMARY_REPORT="${REPORT_DIR}/summary-${TIMESTAMP}.json"
cat > "${SUMMARY_REPORT}" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repository": "${REPO_ROOT}",
  "scan_type": "comprehensive_secret_sprawl_detection",
  "total_findings": ${TOTAL_FINDINGS},
  "scanned_with": [
    "detect-secrets",
    "gitleaks",
    "pip-audit",
    "bandit",
    "pattern_matching"
  ],
  "report_directory": "${REPORT_DIR}"
}
EOF

echo "✅ Scan reports saved to: ${REPORT_DIR}"
echo ""

# Return error if findings detected
if [ "${TOTAL_FINDINGS}" -gt 0 ]; then
  echo "❌ SECURITY ALERT: Secret sprawl detected!"
  echo ""
  echo "Action Required:"
  echo "1. Review reports in: ${REPORT_DIR}"
  echo "2. Remediate immediately (do not commit secrets)"
  echo "3. Rotate any exposed credentials"
  echo "4. Update .secrets.baseline after remediation"
  echo ""
  exit 1
fi

echo "🟢 ALL SECURITY CHECKS PASSED"
exit 0
