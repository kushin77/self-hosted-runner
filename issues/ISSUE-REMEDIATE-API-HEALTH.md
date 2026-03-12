Title: Remediate API health failure caused by idle-cleanup shutdowns

Status: in-progress

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
