#!/bin/bash
# QUICK REFERENCE - Production Hardening Suite
# Copy-paste commands for immediate operations

cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════╗
║         PRODUCTION HARDENING SUITE - QUICK REFERENCE                   ║
║         kushin77/self-hosted-runner (2026-03-14)                       ║
╚══════════════════════════════════════════════════════════════════════════╝

🚀 IMMEDIATE DEPLOYMENT (Copy & Paste)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Step 1: Reload systemd configuration
sudo systemctl daemon-reload
sudo systemctl reset-failed

# Step 2: Verify hardening applied (should show ProtectHome=yes, etc.)
systemctl show credential-rotation.service | grep -E 'Protect|Private|Restrict'

# Step 3: Initialize audit log signing
bash scripts/ssh_service_accounts/audit_log_signer.sh init

# Step 4: Run preflight validation (blocks if critical issues)
bash scripts/ssh_service_accounts/preflight_health_gate.sh

# Step 5: Restart service with hardening
sudo systemctl restart credential-rotation.service
sudo journalctl -u credential-rotation.service -n 20

# Step 6: First hardened rotation (integrates all enhancements)
bash scripts/ssh_service_accounts/rotate_all_service_accounts.sh rotate-all

# Step 7: Verify audit integrity (detects tampering)
bash scripts/ssh_service_accounts/audit_log_signer.sh verify

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔎 DAILY OPERATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Check system health
bash scripts/ssh_service_accounts/preflight_health_gate.sh

# Verify audit trail integrity
bash scripts/ssh_service_accounts/audit_log_signer.sh verify

# Check for quarantined accounts (require manual fix)
bash scripts/ssh_service_accounts/rotation_rollback_handler.sh quarantine

# View change history (last 30)
bash scripts/ssh_service_accounts/change_control_tracker.sh history 30

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🆘 TROUBLESHOOTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Health gate fails? Auto-fix minor issues
bash scripts/ssh_service_accounts/preflight_health_gate.sh --fix-minor

# Account rotated back? Check quarantine
bash scripts/ssh_service_accounts/rotation_rollback_handler.sh quarantine

# Quarantine set? Fix issue then clear
bash scripts/ssh_service_accounts/rotation_rollback_handler.sh clear <account>

# Audit integrity check failed? Force re-sign
bash scripts/ssh_service_accounts/audit_log_signer.sh sign
bash scripts/ssh_service_accounts/audit_log_signer.sh verify

# Show what changed recently?
bash scripts/ssh_service_accounts/change_control_tracker.sh history 50

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 COMPLIANCE QUERIES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# All changes in last 24 hours
bash scripts/ssh_service_accounts/change_control_tracker.sh summary 24

# All failed operations
jq '.[] | select(.status=="failed")' logs/change-control.jsonl

# All changes by specific user
jq '.[] | select(.user=="akushnir")' logs/change-control.jsonl

# Timeline of credential rotations
jq '.[] | select(.operation=="credential_rotation")' logs/change-control.jsonl | \
  jq -s 'sort_by(.timestamp) | .[-10:]'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📝 MAINTENANCE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Weekly: Check rotation status
bash scripts/ssh_service_accounts/rotate_all_service_accounts.sh report

# Weekly: Audit trail review
bash scripts/ssh_service_accounts/rotate_all_service_accounts.sh audit | tail -20

# Monthly: Archive old change-control entries
bash scripts/ssh_service_accounts/change_control_tracker.sh cleanup 10000

# Monthly: Backup audit logs for compliance
cp logs/credential-audit.jsonl logs/archive/audit-$(date +%Y%m%d).jsonl
cp logs/credential-audit.jsonl.signatures logs/archive/sigs-$(date +%Y%m%d)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 COMMAND SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AUDIT LOG SIGNER
  bash audit_log_signer.sh init              # Initialize (one-time)
  bash audit_log_signer.sh sign              # Sign new entries
  bash audit_log_signer.sh verify            # Verify integrity (tampering detection)
  bash audit_log_signer.sh status            # Show current signatures + hash

ROLLBACK HANDLER
  bash rotation_rollback_handler.sh check <account>       # Health check + auto-rollback
  bash rotation_rollback_handler.sh rollback <account>    # Manual rollback
  bash rotation_rollback_handler.sh quarantine            # List quarantined accounts
  bash rotation_rollback_handler.sh clear <account>       # Clear quarantine

PREFLIGHT GATE
  bash preflight_health_gate.sh                       # Full validation
  bash preflight_health_gate.sh --fix-minor          # Auto-fix minor issues

CHANGE CONTROL
  bash change_control_tracker.sh history [limit]              # View recent changes
  bash change_control_tracker.sh search <term>                # Search history
  bash change_control_tracker.sh summary [hours]              # Statistics
  bash change_control_tracker.sh cleanup [keep-count]         # Archive old entries

ROTATION (With all enhancements)
  bash rotate_all_service_accounts.sh rotate-all      # Full rotation (preflight + rollback + signing)
  bash rotate_all_service_accounts.sh report           # Status report
  bash rotate_all_service_accounts.sh audit            # Audit trail (recent 20)
  bash rotate_all_service_accounts.sh health           # Health checks on all credentials

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔗 RESOURCES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Documentation:
  • HARDENING_AND_AUTOMATION_COMPLETE_20260314.md (comprehensive guide)
  • PRODUCTION_HARDENING_DEPLOYMENT_REPORT_20260314.md (detailed report)

GitHub Issues (full technical details):
  • #3104 - Enhancement #1: Systemd Sandbox Hardening
  • #3105 - Enhancement #2: Audit Log Hash-Chain Signing
  • #3106 - Enhancement #3: Rotation Rollback Handler
  • #3107 - Enhancement #4: Preflight Health Gate
  • #3108 - Enhancement #5: Change-Control Automation
  • #3109 - Complete Implementation Summary

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Status: ALL ENHANCEMENTS DEPLOYED AND OPERATIONAL
🚀 Ready for immediate deployment: systemctl daemon-reload
📞 Questions? Review GitHub issues #3104-#3108 for technical details

EOF
