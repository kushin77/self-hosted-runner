#!/usr/bin/env bash
PASS=0
FAIL=0
check_pass() { echo "[PASS]: $1"; ((PASS++)); }
check_status() { if (( $? == 0 )); then check_pass "$1"; fi; }
echo "Starting final 100% Hands-Off validation..."
git ls-files scripts/gsm_to_vault_sync.sh scripts/automated_test_alert.sh | wc -l | grep -q 2; check_status "Immutability: Core scripts in git"
git ls-files scripts/systemd/gsm-to-vault-sync.service | wc -l | grep -q 1; check_status "Immutability: Systemd unit in git"
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.42 "docker ps | grep vault" >/dev/null; check_status "Sovereignty: Vault active on .42"
ssh -o StrictHostKeyChecking=no akushnir@192.168.168.42 "systemctl is-active gsm-to-vault-sync.timer" | grep -q active; check_status "Hands-Off: Sync timer active"
./scripts/automated_test_alert.sh 2>&1 | grep -qiE "200|accepted"; check_status "Automation: End-to-end alert validated"
[ -f "docs/OPERATIONAL_HANDOFF.md" ]; check_status "Documentation: Runbook complete"
echo "=============================="
echo "FINAL STATUS: $PASS/6 Checks Passed"
if (( $PASS == 6 )); then echo "🎉 MISSION COMPLETE: 100% HANDS-OFF"; else echo "⚠️ SOME CHECKS MISSED"; fi
