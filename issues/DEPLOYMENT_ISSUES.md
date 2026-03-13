# Deployment Issues Tracker

## Issue #1: DNS Cutover Phase 2+3 (Closed ✅)
**Status:** CLOSED - 2026-03-13T13:49:44Z
- Phase 1 (Canary): ✅ Complete
- Phase 2 (Full Promotion): ✅ Complete
- Phase 3 (Notifications): ✅ Complete (notification attempted; see Issue #2)
- Target: 192.168.168.42 on-prem
- Logs: logs/cutover/execution_full_20260313T134942Z.log
- Post-run: Phase 4 (24h validation) active — monitor Grafana/Prometheus

## Issue #2: Slack Webhook Configuration (Operational)
**Status:** ACTION REQUIRED - Webhook unreachable during Phase 3
- Current: `slack-webhook` in GSM present but delivery attempts failed during finalization
- Evidence: `logs/cutover/execution_full_20260313T134942Z.log` contains `Slack notification delivery failed (webhook unreachable)` entries
- Impact: Non-blocking for DNS cutover; reduces operator alerting
- Recommended Action:
	1. Verify `slack-webhook` secret in GSM and re-inject if placeholder or invalid.
	2. From runner, test webhook egress: `curl -sS -X POST -H 'Content-type: application/json' --data '{"text":"test"}' $(gcloud secrets versions access latest --secret=slack-webhook --project=nexusshield-prod)`
	3. Re-run idempotent notifications step: `bash scripts/ops/retry-notifications.sh` (non-destructive)
	4. Consider alternate notification channels if Slack remains unreachable.

## Issue #3: AWS Credentials (Optional)
**Status:** OPTIONAL - Route53 fallback available but not configured
- Current: Route53 not authenticated
- Status: Cloudflare primary (✅) available; no action needed
- Action: None required (not blocking)

## Post-Deployment Checklist
- [ ] Monitor Grafana (http://192.168.168.42:3000) for 24h
- [ ] Verify all 13 services running: `curl -s http://192.168.168.42:9090/api/v1/query?query=up | jq`
- [ ] Error rate <0.1% (from Prometheus)
- [ ] No DNS failures reported by clients
- [ ] Close this issue once 24h validation complete

## Governance Compliance (All ✅)
- ✅ Immutable: All actions logged to JSONL + git
- ✅ Ephemeral: Secrets fetched from GSM (no long-lived creds)
- ✅ Idempotent: Full promotion completed successfully; re-running is safe
- ✅ No-Ops: All automation ran unattended (Phase 1-3 complete)
- ✅ Hands-Off: No manual DNS changes required; GSM token auto-fetched
- ✅ GSM/Vault/KMS: All creds from GSM (cloudflare-api-token, slack-webhook)
- ✅ Direct Deployment: No GitHub Actions used; direct script execution
- ✅ No GitHub Releases: No PR-based deployments; direct commit to main
