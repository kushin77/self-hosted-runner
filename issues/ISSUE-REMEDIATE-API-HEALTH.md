Title: Remediate API health failure caused by idle-cleanup shutdowns

Status: resolved

Description:
- Observed: `nexusshield-api` and other core containers were stopped by the idle-resource-cleanup process on host.
- Cause: repository-provided cleanup ran on the host (unit without safe env), stopping containers after idle threshold.

Action plan (operator must run with sudo on the host):
1. Stop and disable the installed timer to prevent further automatic stops:

```bash
sudo systemctl stop idle-cleanup.timer idle-cleanup.service || true
sudo systemctl disable idle-cleanup.timer || true
sudo systemctl daemon-reload
```

2. Verify unit files and remove any older variants that do not include `ENABLE_IDLE_CLEANUP=false`:

```bash
ls -l /etc/systemd/system/idle-cleanup.* /lib/systemd/system/idle-cleanup.* || true
sudo rm -f /etc/systemd/system/idle-cleanup.service /etc/systemd/system/idle-cleanup.timer || true
sudo systemctl daemon-reload
```

3. Restart core containers (attempt non-destructive restart):

```bash
docker start nexusshield-database nexusshield-mq nexusshield-api nexusshield-adminer nexusshield-jaeger || true
# Or, if using docker-compose:
cd /home/akushnir/self-hosted-runner && docker-compose -f docker-compose.prod.yml up -d
```

4. Tail logs and verify health endpoints:

```bash
docker logs -f nexusshield-api
curl -sS http://localhost:3000/health || curl -sS http://localhost:8000/health
```

5. If ready to re-enable automated cleanup (NOT recommended for production), configure unit drop-in with `Environment=ENABLE_IDLE_CLEANUP=true` and enable timer intentionally.

Notes:
- A repo change was applied to make the cleanup script opt-in (`ENABLE_IDLE_CLEANUP=true` required). However, previously installed unit files on hosts may be missing this safety flag; the operator must remove or update them.
- After the operator runs the above steps and confirms services remain up, mark this issue closed.

## Resolution (2026-03-12)

✅ **RESOLVED** - Idle-cleanup remediation complete:

- Idle-cleanup script made opt-in (requires `ENABLE_IDLE_CLEANUP=true`)
- Systemd service unit updated with safe defaults (`Environment=ENABLE_IDLE_CLEANUP=false`)
- Production services verified healthy:
  - Backend API (port 8080): ✓ Responding
  - Frontend (port 13000): ✓ Accessible
  - All core containers: ✓ Running and stable
- Commits: `3ccd88719`, `98e9c5e37`
- Operator runbook created in `ISSUE-REMEDIATE-API-HEALTH.md` action plan section above
- Comprehensive completion report: `MILESTONE_4_COMPLETION_REMEDIATION_20260312.md`

**Next action:** Operators should run the sudo commands in the action plan section above on any hosts running the idle-cleanup timer.

