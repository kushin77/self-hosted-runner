#!/usr/bin/env bash
##
## Host Verification Script
## Checks critical security posture before runner bootstrap.
##
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() {
  echo -e "${GREEN}✓${NC} $*"
}

fail() {
  echo -e "${RED}✗${NC} $*"
  return 1
}

warn() {
  echo -e "${YELLOW}⚠${NC} $*"
}

echo "Host Verification for CI/CD Runner"
echo "===================================="

checks_passed=0
checks_failed=0

# Check kernel version
if uname -r | grep -qE '[4-9]\.[0-9]+'; then
  pass "Kernel version $(uname -r) supported"
  ((checks_passed++))
else
  fail "Kernel version too old"
  ((checks_failed++))
fi

# Check CPU
if [ "$(nproc)" -ge 2 ]; then
  pass "CPU: $(nproc) cores"
  ((checks_passed++))
else
  fail "Insufficient CPU cores (require >= 2)"
  ((checks_failed++))
fi

# Check memory
mem_gb=$(free -g | awk 'NR==2 {print $2}')
if [ "${mem_gb}" -ge 4 ]; then
  pass "Memory: ${mem_gb}GB"
  ((checks_passed++))
else
  fail "Insufficient memory (require >= 4GB)"
  ((checks_failed++))
fi

# Check disk space
disk_gb=$(df / | awk 'NR==2 {printf "%d", $4 / 1024 / 1024}')
if [ "${disk_gb}" -ge 50 ]; then
  pass "Disk space: ${disk_gb}GB available"
  ((checks_passed++))
else
  fail "Insufficient disk space (require >= 50GB)"
  ((checks_failed++))
fi

# Check SELinux or AppArmor
if command -v getenforce &>/dev/null; then
  selinux_status=$(getenforce)
  pass "SELinux: ${selinux_status}"
  ((checks_passed++))
elif command -v aa-status &>/dev/null; then
  pass "AppArmor: enabled"
  ((checks_passed++))
else
  warn "No MAC framework (SELinux/AppArmor) detected"
fi

# Check firewall
if systemctl is-active --quiet ufw || systemctl is-active --quiet firewalld; then
  pass "Firewall: active"
  ((checks_passed++))
else
  warn "Firewall not detected or inactive"
fi

# Check for required binaries
required_bins=("git" "curl" "docker" "systemctl")
for bin in "${required_bins[@]}"; do
  if command -v "${bin}" &>/dev/null; then
    pass "Binary: ${bin}"
    ((checks_passed++))
  else
    fail "Missing binary: ${bin}"
    ((checks_failed++))
  fi
done

# Security checks: file permissions
if [ "$(stat -c %a /root)" == "700" ]; then
  pass "Root home permissions: 700"
  ((checks_passed++))
else
  warn "Root home permissions not optimal"
fi

# Check for secure boot (optional on modern systems)
if [ -d /sys/firmware/efi ]; then
  pass "UEFI boot detected"
  ((checks_passed++))
fi

echo ""
echo "Summary: ${checks_passed} passed, ${checks_failed} failed"

if [ "${checks_failed}" -gt 0 ]; then
  echo "⚠️  Fix failures before proceeding with bootstrap"
  exit 1
fi

echo "✓ Host security verification passed"
exit 0
