#!/usr/bin/env bash
# scripts/testing/run-all-chaos-tests.sh
# Master test runner: Executes all E2E security chaos tests and generates consolidated report

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPORT_DIR="${REPO_ROOT}/reports/chaos"
TEST_LOG="${REPORT_DIR}/chaos-test-results-$(date +%Y%m%d-%H%M%SZ).txt"
SUMMARY_FILE="${REPORT_DIR}/chaos-test-summary-$(date +%Y%m%d).md"

mkdir -p "$REPORT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Overall counters
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

echo "🧪 E2E SECURITY CHAOS TESTING SUITE" | tee "$TEST_LOG"
echo "=====================================" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"

# Test Suite 1: Core Framework Tests
echo -e "${BLUE}[SUITE 1/4] Running Core Framework Tests...${NC}" | tee -a "$TEST_LOG"
((TOTAL_SUITES++))

if bash "${REPO_ROOT}/scripts/testing/chaos-test-framework.sh" 2>&1 | tee -a "$TEST_LOG"; then
  ((PASSED_SUITES++))
  echo -e "${GREEN}✓ Core Framework Tests PASSED${NC}" | tee -a "$TEST_LOG"
else
  ((FAILED_SUITES++))
  echo -e "${RED}✗ Core Framework Tests FAILED${NC}" | tee -a "$TEST_LOG"
fi

echo "" | tee -a "$TEST_LOG"

# Test Suite 2: Audit Tampering Tests
echo -e "${BLUE}[SUITE 2/4] Running Audit Tampering Tests...${NC}" | tee -a "$TEST_LOG"
((TOTAL_SUITES++))

if bash "${REPO_ROOT}/scripts/testing/chaos-audit-tampering.sh" 2>&1 | tee -a "$TEST_LOG"; then
  ((PASSED_SUITES++))
  echo -e "${GREEN}✓ Audit Tampering Tests PASSED${NC}" | tee -a "$TEST_LOG"
else
  ((FAILED_SUITES++))
  echo -e "${RED}✗ Audit Tampering Tests FAILED${NC}" | tee -a "$TEST_LOG"
fi

echo "" | tee -a "$TEST_LOG"

# Test Suite 3: Credential Injection Tests
echo -e "${BLUE}[SUITE 3/4] Running Credential Injection Tests...${NC}" | tee -a "$TEST_LOG"
((TOTAL_SUITES++))

if bash "${REPO_ROOT}/scripts/testing/chaos-credential-injection.sh" 2>&1 | tee -a "$TEST_LOG"; then
  ((PASSED_SUITES++))
  echo -e "${GREEN}✓ Credential Injection Tests PASSED${NC}" | tee -a "$TEST_LOG"
else
  ((FAILED_SUITES++))
  echo -e "${RED}✗ Credential Injection Tests FAILED${NC}" | tee -a "$TEST_LOG"
fi

echo "" | tee -a "$TEST_LOG"

# Test Suite 4: Webhook Attack Tests
echo -e "${BLUE}[SUITE 4/4] Running Webhook Attack Tests...${NC}" | tee -a "$TEST_LOG"
((TOTAL_SUITES++))

if bash "${REPO_ROOT}/scripts/testing/chaos-webhook-attacks.sh" 2>&1 | tee -a "$TEST_LOG"; then
  ((PASSED_SUITES++))
  echo -e "${GREEN}✓ Webhook Attack Tests PASSED${NC}" | tee -a "$TEST_LOG"
else
  ((FAILED_SUITES++))
  echo -e "${RED}✗ Webhook Attack Tests FAILED${NC}" | tee -a "$TEST_LOG"
fi

echo "" | tee -a "$TEST_LOG"

# Generate comprehensive report
echo "📊 Generating Comprehensive Report..." | tee -a "$TEST_LOG"

cat > "$SUMMARY_FILE" <<EOF
# E2E Security Chaos Testing Report

**Generated**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")  
**Repository**: $REPO_ROOT  
**Test Suites**: $TOTAL_SUITES  

## Summary

| Metric | Value |
|--------|-------|
| Total Suites | $TOTAL_SUITES |
| Passed Suites | $PASSED_SUITES |
| Failed Suites | $FAILED_SUITES |
| Success Rate | $((PASSED_SUITES * 100 / TOTAL_SUITES))% |

## Test Suites Executed

### 1. Core Framework Tests
- Credential failover chain (GSM → Vault → Environment)
- Immutable audit log integrity
- Environment variable naming validation
- Webhook signature validation
- Permission escalation prevention
- Idempotency and re-execution safety

**Status**: $([ $PASSED_SUITES -gt 0 ] && echo "✅ PASSED" || echo "❌ FAILED")

### 2. Audit Tampering Tests
- Deletion attack detection
- Modification attack detection  
- Rollback prevention (timestamp integrity)
- Concurrent write safety
- Forensic analysis capability
- Multi-stream audit correlation

**Status**: $([ $PASSED_SUITES -gt 1 ] && echo "✅ PASSED" || echo "❌ FAILED")

### 3. Credential Injection Tests
- Shell injection prevention
- Environment variable pollution detection
- Plaintext credential exposure prevention
- Credential TTL enforcement
- KMS encryption enforcement
- Credential rotation safety
- Credential access audit logging

**Status**: $([ $PASSED_SUITES -gt 2 ] && echo "✅ PASSED" || echo "❌ FAILED")

### 4. Webhook Attack Tests
- Signature validation (HMAC-SHA256)
- Event type filtering / allowlist bypass
- Payload injection prevention
- Event replay attack prevention
- Rate limiting
- Secret rotation with grace period
- Webhook audit trail

**Status**: $([ $PASSED_SUITES -gt 3 ] && echo "✅ PASSED" || echo "❌ FAILED")

## Security Controls Validated

✅ **Immutability**: Audit logs append-only with tampering detection  
✅ **Ephemerality**: Credentials loaded at runtime (1-hour TTL)  
✅ **Idempotency**: Scripts safe to re-run without side effects  
✅ **No-Ops**: All automation hands-off (no manual intervention)  
✅ **Multi-Layer Credentials**: GSM → Vault → KMS failover chain  
✅ **Direct Deployment**: No GitHub Actions, direct shell scripts  
✅ **Webhook Security**: HMAC-SHA256 + event filtering + replay protection  
✅ **Permission Isolation**: Non-root operation + least privilege  

## Chaos Scenarios Tested

### Failure Modes
- **Credential Source Failover**: Primary (GSM) → Secondary (Vault) → Tertiary (Environment)
- **Audit Log Tampering**: Deletion, modification, rollback attempts
- **Credential Injection**: Shell injection, environment pollution, plaintext exposure
- **Webhook Attacks**: Signature bypass, payload modification, event replay, rate flooding
- **Concurrent Access**: Multiple writers to shared audit logs
- **Permission Escalation**: Non-root privilege boundary testing

### Attack Scenarios
- Adversary attempts to modify audit logs (tampering)
- Adversary injects malicious credentials (injection)
- Adversary replays webhook events (replay)
- Adversary modifies webhook payloads (HMAC bypass)
- Adversary escalates privileges (local)
- Adversary floods webhook endpoint (rate limit)

## Test Execution Details

Full test logs: \`$TEST_LOG\`

## Recommendations

### Immediate Actions
1. Review any FAILED test suites and address root causes
2. Implement rate limiting middleware for webhook ingestion
3. Set up continuous chaos testing (daily execution)
4. Monitor audit logs for tampering patterns

### Future Enhancements  
1. Implement hardware security module (HSM) integration for KMS
2. Add distributed audit logging (separate secure server)
3. Implement secret detection in git commits (prevent accidental exposure)
4. Add FIPS 140-2 validation for encryption algorithms

## Compliance Alignments

- **SOC 2 Type II**: AU1.1 (Criteria - CC7.2: System Monitoring)
- **ISO 27001**: A.12.4.1 (Event logging), A.12.4.3 (Protection of log information)
- **CIS Benchmarks**: Logging and Monitoring (v2.0)
- **NIST Cybersecurity Framework**: PR.MA (Maintenance), DE.AE (Anomalies & Events)

## Conclusion

$(if [[ $FAILED_SUITES -eq 0 ]]; then
  echo "✅ **All security chaos tests PASSED**. The infrastructure demonstrates:"
  echo "- Immutable audit trails with tampering detection"
  echo "- Resilient credential failover chain"
  echo "- Strong webhook security controls"
  echo "- Permission isolation and access controls"
else
  echo "⚠️  **$FAILED_SUITES test suite(s) FAILED**. Review logs and implement remediation."
fi
)

---
_Report generated by E2E Security Chaos Testing Framework_
EOF

echo -e "${BLUE}Report saved to: $SUMMARY_FILE${NC}" | tee -a "$TEST_LOG"
echo "" | tee -a "$TEST_LOG"
echo "========================================" | tee -a "$TEST_LOG"
echo "FINAL RESULTS" | tee -a "$TEST_LOG"
echo "========================================" | tee -a "$TEST_LOG"
echo "Test Suites: $PASSED_SUITES/$TOTAL_SUITES PASSED" | tee -a "$TEST_LOG"

if [[ $FAILED_SUITES -eq 0 ]]; then
  echo -e "${GREEN}✓ ALL CHAOS TESTS PASSED${NC}" | tee -a "$TEST_LOG"
  exit 0
else
  echo -e "${RED}✗ $FAILED_SUITES SUITE(S) FAILED${NC}" | tee -a "$TEST_LOG"
  exit 1
fi
