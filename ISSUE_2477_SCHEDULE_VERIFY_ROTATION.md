Title: Schedule verify-rotation test on internal runner

Description:
- Ensure `scripts/tests/verify-rotation.sh` is scheduled to run nightly on an internal runner.
- This test publishes a message to `rotate-uptime-token-topic` and verifies that a new secret version appears in GSM and Cloud Run envs are updated.

Acceptance Criteria:
- Cron schedule: nightly at 04:00 UTC (or configurable)
- Test execution logs are stored in `gs://nexusshield-ops-logs/verify-rotation/`
- On failure, post to `#ops-alerts` and create an incident ticket.

Notes:
- PR not allowed; create as direct deployment job in internal orchestration system.
- Related issues: ISSUE_2468 (Phase 4.3 external uptime checks), ISSUE_2469 (Phase 4.4 compliance)
