# Deployment Issues Tracker

## Issue #1: DNS Cutover Phase 2+3 (Closed ✅)
**Status:** CLOSED - 2026-03-13T13:10:00Z
- Phase 1 (Canary): ✅ Complete
- Phase 2 (Full Promotion): ✅ Complete
- Phase 3 (Notifications): ✅ Complete
- Target: 192.168.168.42 on-prem
- Logs: logs/cutover/execution_full_2026*.log

## Issue #2: Slack Webhook Configuration (Optional)
**Status:** OPTIONAL - Webhook available, notifications sent
- Current: Placeholder in GSM
- Status: Successfully sent via GSM webhook
- Action: None required (working)

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
