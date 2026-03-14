# SSH Deployment Checklist & Best Practices

**Status:** ✅ **MANDATORY DEPLOYMENT GUIDE**  
**Effective:** 2026-03-14  
**Applies To:** All SSH service account deployments  
**Review Cycle:** Quarterly

---

## Pre-Deployment Security Checklist

### Phase 0: Environment Validation

- [ ] **SSH_ASKPASS Configuration**
  ```bash
  [ "$SSH_ASKPASS" = "none" ] || exit 1
  [ "$SSH_ASKPASS_REQUIRE" = "never" ] || exit 1
  [ -z "$DISPLAY" ] || exit 1
  ```

- [ ] **SSH Config Validation**
  ```bash
  grep -q "PasswordAuthentication no" ~/.ssh/config
  grep -q "PubkeyAuthentication yes" ~/.ssh/config
  grep -q "BatchMode yes" ~/.ssh/config
  ```

- [ ] **Key Permissions Verification**
  ```bash
  test "$(stat -c %a ~/.ssh/svc-keys/*_key)" = "600" || exit 1
  ```

- [ ] **SSH Command Testing**
  ```bash
  # Should fail quickly, NOT prompt for password
  timeout 2 ssh -o BatchMode=yes -i ~/.ssh/svc-keys/test_key test@127.0.0.1 whoami 2>&1 | \
      grep -qE "Permission denied|Connection refused" || exit 1
  ```

- [ ] **No sshpass or expect Usage**
  ```bash
  grep -r "sshpass\|expect\|interact\|send password" scripts/ || true
  # If found: manual review + removal required
  ```

### Phase 1: Secret Storage Validation

- [ ] **GSM Availability Check**
  ```bash
  gcloud secrets list --project="$GCP_PROJECT_ID" --format="table(name)" | \
      grep -q "elevatediq-svc-worker-dev" || exit 1
  ```

- [ ] **Key Retrieval Test**
  ```bash
  gcloud secrets versions access latest \
      --secret="elevatediq-svc-worker-dev" \
      --project="$GCP_PROJECT_ID" > /tmp/test-key
  
  # Verify it's a valid Ed25519 key
  ssh-keygen -l -f /tmp/test-key | grep -q "ED25519" || exit 1
  
  # Securely delete test key
  shred -vfz -n 3 /tmp/test-key
  ```

- [ ] **Vault Connectivity (if secondary)**
  ```bash
  curl -s "$VAULT_ADDR/v1/auth/token/lookup-self" \
      -H "X-Vault-Token: $VAULT_TOKEN" | jq -e '.auth.token_ttl' > /dev/null
  ```

- [ ] **Key Encryption Verification**
  ```bash
  # GSM encryption at rest
  gcloud secrets describe "elevatediq-svc-worker-dev" \
      --project="$GCP_PROJECT_ID" | grep -q "replication" || exit 1
  ```

### Phase 2: Target Host Validation

- [ ] **SSH Connectivity (no password)**
  ```bash
  ssh -o BatchMode=yes \
      -o ConnectTimeout=5 \
      -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key \
      elevatediq-svc-worker-dev@192.168.168.42 "whoami" \
      > /dev/null || exit 1
  ```

- [ ] **Service Account Exists on Target**
  ```bash
  ssh -o BatchMode=yes \
      -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key \
      elevatediq-svc-worker-dev@192.168.168.42 \
      "id elevatediq-svc-worker-dev" > /dev/null || exit 1
  ```

- [ ] **Public Key in authorized_keys**
  ```bash
  ssh -o BatchMode=yes \
      -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key \
      elevatediq-svc-worker-dev@192.168.168.42 \
      "grep -q 'ED25519' ~/.ssh/authorized_keys" || exit 1
  ```

- [ ] **No Password Authentication on Server**
  ```bash
  ssh -o BatchMode=yes \
      -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key \
      elevatediq-svc-worker-dev@192.168.168.42 \
      "grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config" || exit 1
  ```

- [ ] **SSH Permissions Correct on Target**
  ```bash
  ssh -o BatchMode=yes \
      -i ~/.ssh/svc-keys/elevatediq-svc-worker-dev_key \
      elevatediq-svc-worker-dev@192.168.168.42 \
      "test \$(stat -c %a ~/.ssh) = 700 && test \$(stat -c %a ~/.ssh/authorized_keys) = 600" || exit 1
  ```

### Phase 3: Deployment Verification

- [ ] **Create State Tracking File**
  ```bash
  mkdir -p .deployment-state/elevatediq-svc-worker-dev
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > \
      .deployment-state/elevatediq-svc-worker-dev/.deployed
  ```

- [ ] **Audit Log Entry Created**
  ```bash
  jq -n \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg account "elevatediq-svc-worker-dev" \
      '{
          timestamp: $ts,
          event_type: "SSH_DEPLOYMENT",
          service_account: $account,
          status: "deployed",
          auth_type: "publickey",
          password_prompt: false
      }' >> logs/audit-trail.jsonl
  ```

- [ ] **Idempotency Test**
  ```bash
  # Run deployment script 3 times - should be identical result
  for i in 1 2 3; do
      bash scripts/ssh_service_accounts/automated_deploy_keys_only.sh > /tmp/deploy-$i.log 2>&1
  done
  
  diff /tmp/deploy-1.log /tmp/deploy-2.log && \
  diff /tmp/deploy-2.log /tmp/deploy-3.log || exit 1
  ```

- [ ] **Health Check Succeeds**
  ```bash
  bash scripts/ssh_service_accounts/health_check.sh report | \
      grep -q "elevatediq-svc-worker-dev.*HEALTHY" || exit 1
  ```

---

## Post-Deployment Verification

### Hour 1 After Deployment

- [ ] SSH connections still working (no password prompts)
- [ ] Service account able to execute commands
- [ ] Audit log entries populated
- [ ] Zero failed connection attempts
- [ ] Alerts cleared (no SSH connectivity issues)

### Day 1 After Deployment

- [ ] Health check automation enabled
  ```bash
  sudo systemctl enable --now service-account-health-check.timer
  ```

- [ ] Monitoring dashboard shows green
  ```bash
  curl http://prometheus:9090/api/v1/query?query=ssh_connection_success_total
  ```

- [ ] No anomalies in access patterns
- [ ] Key rotation scheduled and confirmed
- [ ] All team members verified in RBAC

### Week 1 After Deployment

- [ ] Zero unplanned SSH failures
- [ ] All deployments using new account succeed
- [ ] No password prompt incidents reported
- [ ] Compliance log audit complete
- [ ] Team trained on new account usage

---

## Code Review Standards for SSH Scripts

### Security Review Checklist

#### Mandatory Elements

- [ ] **SSH_ASKPASS=none** is set at script top
  ```bash
  export SSH_ASKPASS=none
  export SSH_ASKPASS_REQUIRE=never
  export DISPLAY=""
  ```

- [ ] **All SSH commands** include:
  ```bash
  ssh -o BatchMode=yes \
      -o PasswordAuthentication=no \
      -o PubkeyAuthentication=yes \
      -i /path/to/key ...
  ```

- [ ] **No password input mechanisms**
  - No `read -s password` prompts
  - No `sshpass` or `expect` usage
  - No interactive mode in SSH calls

- [ ] **Error handling** for SSH failures
  ```bash
  ssh ... || {
      log_error "SSH connection failed"
      cleanup_and_exit 1
  }
  ```

- [ ] **Key permissions** validated
  ```bash
  [ "$(stat -c %a "$key_file")" = "600" ] || exit 1
  ```

- [ ] **Audit logging** for every SSH operation
  ```bash
  echo "{\"timestamp\": \"$timestamp\", \"event\": \"ssh_connection\", ...}" >> logs/audit-trail.jsonl
  ```

#### Best Practices

- [ ] **Idempotency markers**
  ```bash
  state_file=".deployment-state/$account/.deployed"
  if [ -f "$state_file" ]; then
      log_info "Already deployed at $(cat "$state_file")"
      return 0
  fi
  ```

- [ ] **Timeout protection**
  ```bash
  timeout 30 ssh -o ConnectTimeout=10 ...
  ```

- [ ] **Verbose logging** for debugging
  ```bash
  ssh -v -o BatchMode=yes ... 2>&1 | tee -a logs/deployment-debug.log
  ```

- [ ] **Secure key handling**
  ```bash
  # Use GSM/Vault, never store keys in variables longer than needed
  key_data=$(gcloud secrets versions access latest --secret="$account")
  ssh -i <(echo "$key_data") ...  # Use process substitution
  unset key_data  # Clear from memory
  ```

#### Testing Requirements

- [ ] **Unit tests** for each function
  ```bash
  test_ssh_key_exists() { [ -f "$key_file" ]; }
  test_ssh_askpass_disabled() { [ "$SSH_ASKPASS" = "none" ]; }
  ```

- [ ] **Integration tests** for full deployment
  ```bash
  bash scripts/ssh_service_accounts/test_ssh_keys_only.sh all
  ```

- [ ] **Dry-run capability**
  ```bash
  bash script.sh --dry-run  # Shows what would happen, doesn't execute
  ```

### A-Grade Script Template

```bash
#!/bin/bash
# SSH Account Deployment - Production Grade
# Enforces SSH key-only authentication
# Status: [DRAFT|REVIEW|APPROVED]

set -euo pipefail
trap 'cleanup_and_exit $?' EXIT INT TERM

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly LOG_DIR="${WORKSPACE_ROOT}/logs"
readonly STATE_DIR="${WORKSPACE_ROOT}/.deployment-state"
readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# SSH Security (MANDATORY)
export SSH_ASKPASS=none
export SSH_ASKPASS_REQUIRE=never
export DISPLAY=""

# Logging functions
log_info() { echo -e "\033[0;34m[INFO]\033[0m $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "\033[0;32m[✓]\033[0m $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "\033[0;31m[✗]\033[0m $1" | tee -a "$LOG_FILE"; }

# Cleanup
cleanup_and_exit() {
    local exit_code=$1
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code $exit_code"
    fi
    exit $exit_code
}

# Validate environment
validate_environment() {
    log_info "Validating environment..."
    
    [ "$SSH_ASKPASS" = "none" ] || {
        log_error "SSH_ASKPASS not properly set"
        return 1
    }
    
    [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
    [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR"
    
    log_success "Environment validated"
}

# Deploy with SSH key-only
deploy_with_keys_only() {
    local account="$1"
    local target="$2"
    local key_path="$3"
    
    log_info "Deploying $account to $target..."
    
    # Validate key permissions
    [ "$(stat -c %a "$key_path")" = "600" ] || {
        log_error "Key permissions incorrect"
        return 1
    }
    
    # Deploy with SSH key-only, no passwords
    ssh -o BatchMode=yes \
        -o PasswordAuthentication=no \
        -o PubkeyAuthentication=yes \
        -o ConnectTimeout=10 \
        -i "$key_path" \
        "$account@$target" \
        "whoami && echo OK" > /dev/null || {
        log_error "SSH deployment failed"
        return 1
    }
    
    # Mark as deployed
    echo "$TIMESTAMP" > "$STATE_DIR/$account/.deployed"
    
    log_success "Deployed $account to $target"
}

# Main
main() {
    local log_file="$LOG_DIR/deployment-${TIMESTAMP}.log"
    
    log_info "Starting SSH key-only deployment"
    validate_environment
    
    # Deploy all accounts...
    
    log_success "Deployment complete"
}

main "$@"
```

---

## Rollback & Recovery Procedures

### Emergency Rollback (If Password Prompt Detected)

```bash
#!/bin/bash
# EMERGENCY: If SSH password prompt detected

# 1. Stop all deployments immediately
sudo systemctl stop nexusshield-auto-deploy.service || true
pkill -f "automated_deploy_keys_only.sh" || true

# 2. Revert to previous key
gcloud secrets versions list "elevatediq-svc-worker-dev" \
    --format="table(name)" | sed -n '2p' | \
    xargs -I {} gcloud secrets versions access {}

# 3. Rotate all keys immediately
bash scripts/ssh_service_accounts/credential_rotation.sh emergency

# 4. Audit log review
jq '.password_prompt == true' logs/audit-trail.jsonl

# 5. Security team notification
# EMAIL: security@nexusshield.io with audit logs
```

### Recovery from Key Exposure

```bash
#!/bin/bash
# If SSH key compromised/exposed

# 1. Generate new Ed25519 key immediately
ssh-keygen -t ed25519 -f secrets/ssh/affected-account/id_ed25519 -N ""

# 2. Create new GSM version
gcloud secrets versions add affected-account \
    --data-file=secrets/ssh/affected-account/id_ed25519

# 3. Distribute new public key to all targets
for host in 192.168.168.42 192.168.168.39; do
    ssh root@$host \
        "sed -i '/old-key-fingerprint/d' /home/affected/.ssh/authorized_keys"
    
    scp secrets/ssh/affected-account/id_ed25519.pub \
        root@$host:/tmp/new-key.pub
    
    ssh root@$host \
        "cat /tmp/new-key.pub >> /home/affected/.ssh/authorized_keys"
done

# 4. Invalidate old key
gcloud secrets versions destroy $(gcloud secrets versions list affected-account \
    --format="table(name)" | sed -n '2p') --secret="affected-account"

# 5. Verify new key works (no password prompt)
ssh -o BatchMode=yes \
    -i secrets/ssh/affected-account/id_ed25519 \
    affected@192.168.168.42 whoami

# 6. Incident report
echo "Incident: SSH key $(date) - $1" >> logs/incident-log.txt
```

---

## Compliance & Audit

### Audit Report Template

```bash
#!/bin/bash
# Generate SSH service account compliance report

report_file="reports/ssh-compliance-$(date +%Y-%m-%d).txt"

{
    echo "SSH Service Account Compliance Report"
    echo "Generated: $(date)"
    echo ""
    
    echo "=== SSH_ASKPASS Configuration ==="
    grep "export SSH_ASKPASS" ~/.bashrc
    
    echo "=== SSH Config ==="
    grep "PasswordAuthentication" ~/.ssh/config
    
    echo "=== Key Inventory ==="
    gcloud secrets list --filter="labels.key_type=ssh-ed25519" \
        --format="table(name, created, updated)"
    
    echo "=== Recent Deployments ==="
    tail -20 logs/deployment-*.log | grep "Deployed\|SUCCESS"
    
    echo "=== Audit Trail Summary ==="
    jq -s 'group_by(.service_account) | map({
        account: .[0].service_account,
        connections: length,
        last_access: max_by(.timestamp).timestamp,
        password_prompts: map(select(.password_prompt==true)) | length
    })' logs/audit-trail.jsonl
    
    echo "=== Alerts ==="
    grep "ERROR\|CRITICAL" logs/*.log | tail -10
    
} | tee "$report_file"

echo "Compliance report: $report_file"
```

---

## Related Documentation

- [SSH_KEY_ONLY_MANDATE.md](../governance/SSH_KEY_ONLY_MANDATE.md) - Policy
- [SERVICE_ACCOUNT_ARCHITECTURE.md](../architecture/SERVICE_ACCOUNT_ARCHITECTURE.md) - Architecture
- [SSH_10X_ENHANCEMENTS.md](../architecture/SSH_10X_ENHANCEMENTS.md) - Future roadmap

---

**Status:** ✅ **MANDATORY DEPLOYMENT CHECKLIST**  
**All Deployments Must Pass:** Phase 0-3  
**Audit Cycle:** Every deployment + Monthly review
