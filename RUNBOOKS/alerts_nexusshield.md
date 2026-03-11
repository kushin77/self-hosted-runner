Title: NexusShield Alerts Runbook

Overview:
This runbook covers alert investigation and remediation steps for NexusShield alerts.

Alert: NexusShieldHighErrorRate
- Check recent logs: sudo journalctl -u cloudrun.service -n 200
- Check health: curl -sS http://127.0.0.1:8080/health
- If transient after deployment: rollback or restart:
  - sudo systemctl restart cloudrun.service
  - sudo systemctl restart redis-worker.service
- Escalate to on-call if persists.

Alert: NexusShieldLongJobDuration
- List running jobs via files under /opt/nexusshield/scripts/data/jobs
- Inspect audit trail for step timeouts
- Increase worker capacity or investigate external systems

Alert: NexusShieldJobCompletionFailures
- Verify redis-worker service and Redis connectivity
- Check `runner-redis-password` in GSM

Contact: ops-oncall
