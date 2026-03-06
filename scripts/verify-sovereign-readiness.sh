#!/bin/bash
set -e
echo "==== SOVEREIGN DR READINESS AUDIT ===="
echo "1. Core Orchestrator: $([ -x scripts/ci/hands_off_dr_orchestration.sh ] && echo 'OK' || echo 'MISSING')"
echo "2. YubiKey Bootstrap: $([ -x scripts/ci/hands_off_yubikey_bootstrap.sh ] && echo 'OK' || echo 'MISSING')"
echo "3. Slack Bridge: $([ -f ci_templates/dr-slack-bridge.yml ] && echo 'OK' || echo 'MISSING')"
echo "4. Ops Runbook: $([ -f docs/DR_RUNBOOK.md ] && echo 'OK' || echo 'MISSING')"
echo "5. Final Attestation: $([ -f PORTAL_DR_STABILITY_ATTESTATION.md ] && echo 'OK' || echo 'MISSING')"
echo "======================================"
echo "Result: If all OK, run ./scripts/ci/hands_off_yubikey_bootstrap.sh to start."
