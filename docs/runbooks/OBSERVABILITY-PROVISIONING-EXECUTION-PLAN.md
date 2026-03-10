# Observability & Provisioning Execution Plan

**Date:** March 9, 2026  
**Status:** READY FOR EXECUTION  
**Target Host:** 192.168.168.42 (akushnir user)

---

## Issue Summary

The worker node requires provisioning of observability and deployment gate agents:
- HashiCorp Vault Agent (credentials management)
- Filebeat (log shipping to ELK/Datadog)
- Prometheus node_exporter (metrics collection)  
- Release gate enforcement (production approval)

**Primary Issue:** [PROVISION_OBSERVABILITY_AND_GATES_2026_03_09.md](./issues/PROVISION_OBSERVABILITY_AND_GATES_2026_03_09.md)

---

## What's Ready

### 1. Worker Provisioning Script ✅

**Script:** `scripts/provision/worker-provision-agents.sh` (130+ lines)

**What it installs:**
- ✅ HashiCorp Vault 1.16.0 (binary)
- ✅ Vault Agent (systemd service with AppRole auth)
- ✅ Filebeat 8.x (Elasticsearch log shipper)
- ✅ Prometheus node_exporter 1.5.0 (metrics exporter)

**Idempotency:**
- Safe to run multiple times
- Skips components already installed
- Enables systemd services automatically

### 2. Configuration Examples ✅

**Location:** `docs/PROVISIONING_AND_OBSERVABILITY.md` (comprehensive runbook)

**Includes:**
- Vault AppRole configuration
- Filebeat ELK/Datadog setup
- Prometheus scrape targets
- Health check procedures

### 3. Deployment Wrapper ✅

**Enhanced:** `scripts/deploy-idempotent-wrapper.sh`

**New Feature:** Production release gate enforcement
```bash
# Checks for: /opt/release-gates/production.approved
# File must exist and be readable for production deploys
# Staging deploys don't require approval gate
```

---

## Execution Steps (ops team)

### Step 1: Install Agents on Worker (via SSH)

```bash
# SSH to worker
ssh akushnir@192.168.168.42

# Copy provisioning script
scp scripts/provision/worker-provision-agents.sh akushnir@192.168.168.42:/tmp/

# Run with sudo
ssh akushnir@192.168.168.42 'sudo bash /tmp/worker-provision-agents.sh'

# Expected output:
# [2026-03-09T16:00:00Z] Updating apt cache
# [2026-03-09T16:00:05Z] Installing prerequisites
# [2026-03-09T16:00:10Z] Installing HashiCorp Vault 1.16.0
# [2026-03-09T16:00:25Z] Installing Filebeat
# [2026-03-09T16:00:35Z] Installing node_exporter 1.5.0
# [2026-03-09T16:00:40Z] Provisioning complete.
```

### Step 2: Configure Vault AppRole

```bash
# On bastion/control host:
# 1. Create AppRole (if not already exists)
vault auth enable approle || true
vault write auth/approle/role/runner-role \
  secret_id_ttl=60s \
  secret_id_num_uses=0

# 2. Get role-id
ROLE_ID=$(vault read -field=role_id auth/approle/role/runner-role/role-id)

# 3. Generate secret-id
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/runner-role/secret-id)

# 4. Copy credentials to worker
ssh akushnir@192.168.168.42 << 'EOF'
sudo mkdir -p /etc/vault/approle
sudo tee /etc/vault/approle/role-id > /dev/null <<<'${ROLE_ID}'
sudo tee /etc/vault/approle/secret-id > /dev/null <<<'${SECRET_ID}'
sudo chmod 0600 /etc/vault/approle/{role-id,secret-id}
sudo chown vault:vault /etc/vault/approle/{role-id,secret-id}
EOF

# 5. Update Vault Agent config on worker
ssh akushnir@192.168.168.42 'sudo bash' << 'EOF'
cat > /etc/vault/agent.d/agent.hcl <<'VAULT'
pid_file = "/var/run/vault-agent.pid"

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "/etc/vault/approle/role-id"
      secret_id_file_path = "/etc/vault/approle/secret-id"
    }
  }
}

sink "file" {
  path = "/var/lib/vault/token"
}

cache {
  use_auto_auth_token = true
  when_inconsistent   = "retry"
  when_denied         = "retry"
}
VAULT

systemctl restart vault-agent
EOF
```

### Step 3: Configure Filebeat Output (Choose One)

#### Option A: ELK Stack
```bash
ssh akushnir@192.168.168.42 'sudo bash' << 'EOF'
cat > /etc/filebeat/filebeat.yml <<'FILEBEAT'
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /run/app-deployment-state/*.jsonl
    - /opt/app/logs/*.log
    - /var/log/vault-agent.log
  json.message_key: msg
  json.keys_under_root: true

output.elasticsearch:
  hosts: ["elk-host:9200"]
  username: "elastic"
  password: "${ELASTICSEARCH_PASSWORD}"
  index: "deployment-%{+yyyy.MM.dd}"

processors:
  - add_kubernetes_metadata: ~
FILEBEAT

systemctl restart filebeat
EOF
```

#### Option B: Datadog Agent
```bash
ssh akushnir@192.168.168.42 << 'EOF'
export DATADOG_API_KEY="YOUR_API_KEY"
bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
EOF
```

### Step 4: Configure Prometheus Scrape Targets

On your Prometheus instance, add:

```yaml
scrape_configs:
  - job_name: 'runner-deployment'
    static_configs:
      - targets: ['192.168.168.42:9100']
        labels:
          env: 'production'
          role: 'app-worker'
          version: '2026-03-09'
    scrape_interval: 15s
    scrape_timeout: 10s
```

### Step 5: Verify Provisioning

```bash
# Check Vault Agent status
ssh akushnir@192.168.168.42 'sudo systemctl status vault-agent --no-pager'

# Check Filebeat status
ssh akushnir@192.168.168.42 'sudo systemctl status filebeat --no-pager'

# Check node_exporter status
ssh akushnir@192.168.168.42 'sudo systemctl status node_exporter --no-pager'

# Test node_exporter metrics
curl http://192.168.168.42:9100/metrics | head -20

# Test Vault Agent can authenticate
ssh akushnir@192.168.168.42 'cat /var/lib/vault/token'

# Check logs are being collected
ssh akushnir@192.168.168.42 'sudo tail -f /var/log/filebeat/filebeat'
```

---

## Current Worker Status

| Component | Status | Details |
|-----------|--------|---------|
| Vault binary | ✅ Ready (script) | 1.16.0 available |
| Vault Agent config | ✅ Ready (script) | AppRole template provided |
| Filebeat | ✅ Ready (script) | ELK repo configured |
| node_exporter | ✅ Ready (script) | 1.5.0 available |
| Release gate | ✅ Ready (wrapper) | `/opt/release-gates/production.approved` |
| SSH access | ✅ Verified | akushnir@192.168.168.42 |
| Systemd (root) | ⚠️  Needs execution | Requires `sudo` on worker |

---

## Configuration Files to Update

After provisioning, customize these files on the worker:

1. **Vault AppRole Credentials**
   - Copy: `/etc/vault/approle/role-id`
   - Copy: `/etc/vault/approle/secret-id`

2. **Filebeat Config** (one of):
   - `/etc/filebeat/filebeat.yml` (ELK target, credentials)
   - `/etc/datadog-agent/datadog.yaml` (Datadog API key)

3. **Prometheus Scrape Config**
   - Add to Prometheus: `scrape_configs` entry for 192.168.168.42:9100

4. **Production Release Gate**
   - Create: `/opt/release-gates/production.approved` (any content)
   - Approval required before production deployments

---

## Architecture Integration

Once provisioned, the observability stack:

```
Worker (192.168.168.42)
├─ Vault Agent (systemd)
│  └→ Reads AppRole credentials
│     └→ Exposes token to deployment wrapper
├─ Filebeat (systemd)
│  └→ Reads JSON audit logs (/run/app-deployment-state/*.jsonl)
│     └→ Sends to ELK/Datadog for analysis
├─ node_exporter (systemd)
│  └→ Exposes metrics on :9100
│     └→ Scraped by Prometheus every 15s
└─ Deployment Wrapper
   └→ Checks release gate (/opt/release-gates/production.approved)
      └→ Runs idempotent deployment if approved
         └→ Writes immutable JSONL audit logs
```

---

## Rollback Procedure

If provisioning fails:

```bash
# SSH to worker
ssh akushnir@192.168.168.42 'sudo bash' << 'EOF'
  systemctl stop vault-agent filebeat node_exporter
  systemctl disable vault-agent filebeat node_exporter
  # Keep binaries in place (safe to re-run provisioning script)
EOF
```

---

## Next Steps

1. **Ops:** Run worker-provision-agents.sh on 192.168.168.42 (1 command)
2. **Ops:** Configure Vault AppRole credentials (copy 2 files)
3. **Ops:** Configure Filebeat output (update YAML config)
4. **Ops:** Configure Prometheus scrape targets (add 8 lines to prometheus.yml)
5. **System:** Verify connectivity and log/metric ingestion
6. **Verify:** Run deployment validation and check audit logs flow

**Estimated Time:** 10-15 minutes for full setup

---

## References

- **Provisioning Script:** [scripts/provision/worker-provision-agents.sh](./scripts/provision/worker-provision-agents.sh)
- **Configuration Guide:** [docs/PROVISIONING_AND_OBSERVABILITY.md](./docs/PROVISIONING_AND_OBSERVABILITY.md)
- **Deployment Wrapper:** [scripts/deploy-idempotent-wrapper.sh](./scripts/deploy-idempotent-wrapper.sh) (release gate)
- **Issue:** [PROVISION_OBSERVABILITY_AND_GATES_2026_03_09.md](./issues/PROVISION_OBSERVABILITY_AND_GATES_2026_03_09.md)
- **Previous Issue:** [AWS-SECRETS-PROVISIONING-PLAN.md](./AWS-SECRETS-PROVISIONING-PLAN.md)

---

**Status:** Ready for ops team execution  
**Created:** March 9, 2026 16:35 UTC
