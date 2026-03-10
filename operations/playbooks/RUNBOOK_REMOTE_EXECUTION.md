# Runbook: Remote Execution of Comprehensive Deployment Framework

This runbook documents steps to run the comprehensive deployment on a remote "fullstack" host (SSH-accessible).

Prerequisites
- SSH access to remote host (user@host).
- Docker and docker-compose installed on remote host.
- gcloud and terraform installed on remote host.
- Service credentials available (GSM/Vault/KMS or ADC) on remote host.

Quick Steps
1. From local workstation, run:

```bash
# copy artifacts and run remotely (example)
bash scripts/deploy-to-remote-host.sh ubuntu@192.168.168.42 production /home/ubuntu/creds.json
```

2. Monitor remote execution logs (on remote host):

```bash
ssh ubuntu@192.168.168.42
cd /home/akushnir/self-hosted-runner/logs
tail -f comprehensive-deployment-*.jsonl
```

3. Verify services:

```bash
docker-compose -f docker-compose.phase6.yml ps
# check Grafana, Prometheus, Jaeger, API, frontend
```

Failure modes & remediation
- Permission denied enabling APIs on target project (p4-platform):
  • Cause: user/service-account lacks Service Usage Admin or equivalent
  • Fix: add principal to project IAM or provide service account key with the required role

- Docker-compose blocked on local machine:
  • Cause: docker-compose must run on fullstack host
  • Fix: run via `deploy-to-remote-host.sh` or ssh to fullstack host and execute locally

- Credentials not found:
  • Check `GOOGLE_APPLICATION_CREDENTIALS` on remote host or provide `creds.json` during `deploy-to-remote-host.sh`

Notes
- The framework is idempotent; safe to re-run.
- Audit trail: `logs/comprehensive-deployment-*.jsonl` (append-only)
- No GitHub Actions are used; deployment is direct and SSH-based.

Security
- Prefer service-account keys placed in protected location on remote host, or use Vault/GSM where possible.
- Rotate any SA keys after use; use KMS-encrypted secret files if available.

Contact
- For immediate support, SSH into the fullstack host and check logs.
