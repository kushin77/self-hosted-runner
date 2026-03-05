# Deployment Runbook

## Purpose
This runbook documents steps to verify, restart, roll back, and incident-handle the ElevatedIQ services deployed to the worker node (192.168.168.42).

## Services
- `eiq-api` (managed-auth) — port 8080
- `pipeline-repair` — port 8081
- `eiq-portal` (Vite preview) — port 3919
- `provisioner` metrics — port 9090
- Prometheus, Alertmanager, Grafana — ports 9095, 9096, 3000

## Quick Health Checks
Run on the worker node (or via SSH):

```bash
ssh akushnir@192.168.168.42 \
  'curl -fsS http://localhost:8080/health && curl -fsS http://localhost:8081/health'
```

Check systemd services:

```bash
ssh akushnir@192.168.168.42 sudo systemctl status eiq-api pipeline-repair eiq-portal
```

Check ports:

```bash
ssh akushnir@192.168.168.42 netstat -tuln | egrep "8080|8081|3919|9090|9095|9096|3000"
```

## Restarting a service
Example: restart the API service and verify health:

```bash
ssh akushnir@192.168.168.42 sudo systemctl restart eiq-api
sleep 2
ssh akushnir@192.168.168.42 curl -fsS http://localhost:8080/health
```

If a service fails to start, check journal logs:

```bash
ssh akushnir@192.168.168.42 sudo journalctl -u eiq-api -n 200 --no-pager
```

## Rollback procedure
1. If a deployment introduced breaking changes, stop the service: `sudo systemctl stop <service>`.
2. Revert the commit/PR that deployed the change (use PR rollback or git revert on the deployment branch).
3. Re-deploy the previous artifact using the Ansible playbook:

```bash
ansible-playbook -i inventory/hosts ansible/playbooks/deploy-managed-auth-api.yml
```

4. Verify health endpoints and systemd status.

## Post-Incident Actions
- Collect `journalctl` logs and application logs from `/home/akushnir/self-hosted-runner/services/<service>/logs` if present.
- Open a GitHub issue with a concise summary, affected services, timestamps, and relevant logs.

## Contact / Escalation
- Primary: akushnir (SSH access to worker)
- Secondary: infra team on-call (update team contact list)

## Automation / Next Steps
- Add Prometheus alert rules for service down / high error-rate
- Add GitHub Actions job to run `ansible-playbook` on PR merge to `main` (protected, requires manual approval in initial rollout)
- Add log retention/rotation playbook

---
Runbook created: 2026-03-05
