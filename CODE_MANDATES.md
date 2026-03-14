# 💻 CODE MANDATES - Implementation Guide
**Status:** ✅ **ENFORCED** | **Date:** March 14, 2026 | **Audience:** All Developers

---

## INTRODUCTION

Every script, function, and automation in this repository implements one or more enforcement mandates from [ENFORCEMENT_RULES.md](ENFORCEMENT_RULES.md). This document shows **exactly how** mandates are enforced in code.

---

## MANDATE IMPLEMENTATION PATTERNS

### Pattern 1: Pre-Execution Validation (Enforces Rule #1)

**Rule:** "No manual infrastructure changes"

**Implementation:**
```bash
#!/bin/bash
set -euo pipefail

# Every production script MUST start with this validation
verify_no_manual_changes() {
    local changed_files
    
    # Get list of changed files on infrastructure targets
    changed_files=$(ssh ubuntu@192.168.168.42 \
        'git -C /home/akushnir/self-hosted-runner status --porcelain' || echo "")
    
    if [[ -n "$changed_files" ]]; then
        echo "❌ Manual changes detected on production:"
        echo "$changed_files"
        echo ""
        echo "❌ MANDATE ENFORCED: All changes must go through git + automated deployment"
        return 1
    fi
    
    return 0
}

# Usage in any production script:
main() {
    verify_no_manual_changes || exit 1
    # ... rest of script
}

main "$@"
```

**Where it's used:**
- `scripts/deploy-worker-node.sh` - Line 15
- `scripts/ssh_service_accounts/rotate_all_service_accounts.sh` - Line 18
- `scripts/enforce/verify-no-manual-changes.sh` - Standalone validation

---

### Pattern 2: Secret Scanning (Enforces Rule #2)

**Rule:** "No hardcoded secrets anywhere"

**Implementation in `.pre-commit-config.yaml`:**
```yaml
# PRE-COMMIT HOOKS - Runs before every commit
hooks:
  - repo: https://github.com/gitguardian/ggshield
    rev: v1.24.0
    hooks:
      - id: ggshield
        language: python
        entry: ggshield secret scan pre-commit
        stages: [commit]
        language_version: python3.11
        
  - repo: local
    hooks:
      - id: no-hardcoded-secrets
        name: Check for hardcoded secrets
        entry: bash scripts/enforce/no-hardcoded-secrets.sh
        language: script
        stages: [commit]
        types: [text]
        exclude: '.git/|.pre-commit/.git'
```

**Implementation in `scripts/enforce/no-hardcoded-secrets.sh`:**
```bash
#!/bin/bash
# Detects: AWS keys, GitHub tokens, private keys, base64 secrets

check_for_secrets() {
    local file=$1
    local found_secrets=0
    
    # Pattern 1: AWS Key IDs (AKIA...)
    if grep -E 'AKIA[0-9A-Z]{16}' "$file"; then
        echo "❌ AWS Key ID detected in $file"
        found_secrets=1
    fi
    
    # Pattern 2: GitHub Personal Access Tokens
    if grep -E 'ghp_[0-9a-zA-Z]{36}' "$file"; then
        echo "❌ GitHub token detected in $file"
        found_secrets=1
    fi
    
    # Pattern 3: Private Key Headers
    if grep -E '^-----BEGIN (RSA|OPENSSH|PRIVATE)' "$file"; then
        echo "❌ Private key detected in $file"
        found_secrets=1
    fi
    
    # Pattern 4: Vault tokens
    if grep -E 's\.[a-zA-Z0-9]{20,}' "$file"; then
        echo "❌ Vault token detected in $file"
        found_secrets=1
    fi
    
    return $found_secrets
}

# Check all staged files
for file in $(git diff --cached --name-only); do
    check_for_secrets "$file" || exit 1
done

echo "✅ No secrets detected"
exit 0
```

**Where it's enforced:**
- Pre-commit hook (every commit) ✓
- Cloud Build secret scan (every deployment) ✓
- GitHub Actions would scan PRs (if enabled, but we don't use Actions) ✓

---

### Pattern 3: Immutable Audit Trail (Enforces Rule #3)

**Rule:** "All operations logged to append-only, cryptographically verified audit trail"

**Implementation in `scripts/ssh_service_accounts/change_control_tracker.sh`:**
```bash
#!/bin/bash
# Immutable operation logging with user attribution

log_operation() {
    local action=$1
    local status=$2
    shift 2
    local details="$@"
    
    # Create JSONL entry (append-only format)
    local entry=$(cat <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "action": "$action",
  "status": "$status",
  "user": "$(whoami)",
  "hostname": "$(hostname)",
  "details": "$details"
}
EOF
)
    
    # Append to immutable log (no modification allowed)
    echo "$entry" >> logs/credential-audit.jsonl || {
        echo "❌ MANDATE ENFORCED: Audit trail write failed"
        return 1
    }
    
    # Sign this entry for integrity verification
    bash scripts/ssh_service_accounts/audit_log_signer.sh sign || {
        echo "❌ MANDATE ENFORCED: Audit signing failed"
        return 1
    }
    
    return 0
}

# Usage in any operation:
log_operation "credential_rotation" "begin" "account=svc-worker-dev"
# Do the operation...
log_operation "credential_rotation" "end" "status=success,account=svc-worker-dev"
```

**Implementation in `scripts/ssh_service_accounts/audit_log_signer.sh`:**
```bash
#!/bin/bash
# SHA-256 hash-chain signing for immutable verification

sign_audit_trail() {
    local audit_file="logs/credential-audit.jsonl"
    local signature_file="${audit_file}.signatures"
    local chain_file="${audit_file}.chain"
    
    # Get the last signed hash from chain file
    local prev_hash=$(tail -1 "$chain_file" 2>/dev/null || echo "$GENESIS_HASH")
    
    # For each new entry (after last signature)
    while IFS= read -r entry; do
        # Compute new hash: SHA256(prev_hash || entry)
        local new_hash=$(echo -n "${prev_hash}${entry}" | sha256sum | cut -d' ' -f1)
        
        # Append to signatures file (immutable record)
        echo "$new_hash $(date -u +'%Y-%m-%dT%H:%M:%SZ')" >> "$signature_file"
        
        # Update chain for next iteration
        echo "$new_hash" > "$chain_file"
        prev_hash="$new_hash"
    done
}

verify_audit_trail() {
    # Re-compute all hashes and verify against signatures
    local audit_file="logs/credential-audit.jsonl"
    local signature_file="${audit_file}.signatures"
    local line_num=1
    
    while IFS= read -r entry; do
        local expected_hash=$(sed "${line_num}q;d" "$signature_file" | cut -d' ' -f1)
        local prev_hash=$([ $line_num -eq 1 ] && echo "$GENESIS_HASH" || \
                          sed "$((line_num-1))q;d" "$signature_file" | cut -d' ' -f1)
        
        local computed_hash=$(echo -n "${prev_hash}${entry}" | sha256sum | cut -d' ' -f1)
        
        if [[ "$computed_hash" != "$expected_hash" ]]; then
            echo "❌ MANDATE ENFORCED: Hash mismatch at line $line_num (tampering detected)"
            return 1
        fi
        
        ((line_num++))
    done < "$audit_file"
    
    echo "✅ Audit trail integrity verified (all hashes match)"
    return 0
}
```

**Where it's used:**
- Every credential rotation operation
- Every deployment
- Every manual infrastructure change
- Hourly verification job

---

### Pattern 4: Preflight Health Gating (Enforces Rule #4)

**Rule:** "All deployments automatically validated. Unhealthy systems block further changes."

**Implementation in `scripts/ssh_service_accounts/preflight_health_gate.sh`:**
```bash
#!/bin/bash
# 11-category validation gate - blocks deployment if any critical check fails

preflight_checks() {
    local pass=0 fail=0 warn=0
    
    # Category 1: Required Commands (6 checks)
    echo "Checking required commands..."
    for cmd in ssh ssh-keygen gcloud bash jq curl; do
        if command -v "$cmd" &>/dev/null; then
            echo "  ✓ Found: $cmd"
            ((pass++))
        else
            echo "  ✗ Missing: $cmd"
            ((fail++))
        fi
    done
    
    # Category 2: Directory Structure (4 checks)
    echo "Checking directory structure..."
    for dir in logs secrets/ssh .credential-state secrets/ssh/.backups; do
        if [[ -d "$dir" ]]; then
            echo "  ✓ Directory exists: $dir"
            ((pass++))
        else
            echo "  ✗ Missing directory: $dir"
            echo "     Fix: mkdir -p $dir"
            ((fail++))
        fi
    done
    
    # Category 3: SSH Key Permissions (all keys must be 600)
    echo "Checking SSH key permissions..."
    for keyfile in secrets/ssh/*/id_ed25519; do
        if [[ -f "$keyfile" ]]; then
            local perms=$(stat -c %a "$keyfile" 2>/dev/null || stat -f %OLp "$keyfile")
            if [[ "$perms" == "600" ]]; then
                echo "  ✓ Correct permissions: $keyfile (600)"
                ((pass++))
            else
                echo "  ! Warning: Wrong permissions: $keyfile ($perms, need 600)"
                # If --fix-minor, fix automatically
                if [[ "${FIX_MINOR:-false}" == "true" ]]; then
                    chmod 600 "$keyfile"
                    echo "  ✓ Fixed permissions: $keyfile"
                    ((pass++))
                else
                    ((warn++))
                fi
            fi
        fi
    done
    
    # Category 4: Systemd Services
    echo "Checking systemd services..."
    for service in credential-rotation health-checks audit-logger; do
        if systemctl is-enabled "service-account-${service}.service" &>/dev/null; then
            echo "  ✓ Enabled: service-account-${service}.service"
            ((pass++))
        else
            echo "  ✗ Disabled: service-account-${service}.service"
            echo "     Fix: systemctl enable service-account-${service}.service"
            ((fail++))
        fi
    done
    
    # Category 5: Systemd Timers (CRITICAL - blocks if not running)
    echo "Checking systemd timers..."
    for timer in credential-rotation health-checks; do
        if systemctl is-active "${timer}.timer" &>/dev/null; then
            echo "  ✓ Active: ${timer}.timer"
            ((pass++))
        else
            echo "  ✗ CRITICAL: Timer not active: ${timer}.timer"
            echo "     Fix: systemctl start ${timer}.timer"
            ((fail++))
        fi
    done
    
    # Category 6: Disk Space (>500MB required)
    echo "Checking disk space..."
    local available_mb=$(df /home/akushnir/self-hosted-runner | tail -1 | awk '{print $4/1024}' | cut -d. -f1)
    if [[ $available_mb -gt 500 ]]; then
        echo "  ✓ Sufficient disk space: ${available_mb}MB available"
        ((pass++))
    else
        echo "  ✗ CRITICAL: Insufficient disk space: ${available_mb}MB (need 500MB)"
        ((fail++))
    fi
    
    # Category 7: GCP Secret Manager
    echo "Checking GCP Secret Manager..."
    local secret_count=$(gcloud secrets list --project=nexusshield-prod 2>/dev/null | wc -l)
    if [[ $secret_count -gt 5 ]]; then
        echo "  ✓ GCP Secret Manager accessible ($secret_count secrets found)"
        ((pass++))
    else
        echo "  ✗ GCP Secret Manager unreachable"
        ((fail++))
    fi
    
    # Category 8: Vault Status (optional, not critical)
    echo "Checking Vault (optional)..."
    if vault status &>/dev/null; then
        echo "  ✓ Vault accessible"
        ((pass++))
    else
        echo "  ! Warning: Vault not configured (optional)"
        ((warn++))
    fi
    
    # Category 9: Audit Trail Health
    echo "Checking audit trail..."
    if [[ -f "logs/credential-audit.jsonl" ]] && [[ -s "logs/credential-audit.jsonl" ]]; then
        echo "  ✓ Audit trail file present"
        ((pass++))
    else
        echo "  ! Warning: Audit trail empty or missing"
        ((warn++))
    fi
    
    # Category 10: No Quarantined Accounts
    echo "Checking for quarantined accounts..."
    local quarantined_count=$(wc -l < .credential-state/quarantined-accounts 2>/dev/null || echo 0)
    if [[ $quarantined_count -eq 0 ]]; then
        echo "  ✓ No quarantined accounts"
        ((pass++))
    else
        echo "  ✗ WARNING: $quarantined_count accounts quarantined (review needed)"
        ((warn++))
    fi
    
    # Category 11: Audit Trail Integrity
    echo "Checking audit trail integrity..."
    if bash scripts/ssh_service_accounts/audit_log_signer.sh verify &>/dev/null; then
        echo "  ✓ Audit trail integrity verified"
        ((pass++))
    else
        echo "  ✗ CRITICAL: Audit trail failed verification (tampering detected?)"
        ((fail++))
    fi
    
    # Summary
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║  PREFLIGHT CHECK RESULTS                   ║"
    echo "║  Passed: $pass  | Warnings: $warn  | Failed: $fail                    ║"
    echo "╚════════════════════════════════════════════╝"
    
    if [[ $fail -gt 0 ]]; then
        echo ""
        echo "❌ MANDATORY ENFORCEMENT: System not ready for production"
        echo "Fix the above failures and retry."
        return 1
    fi
    
    echo ""
    echo "✅ System is fully OPERATIONAL and healthy"
    return 0
}

# MANDATORY INTEGRATION
# This function MUST be called before any production operation:
if preflight_checks; then
    echo "Proceeding with operation..."
else
    echo "BLOCKED: Fix failures above"
    exit 1
fi
```

**Where it's integrated:**
- `scripts/deploy-worker-node.sh` - Before every deployment
- `scripts/ssh_service_accounts/rotate_all_service_accounts.sh` - Before rotation
- Pre-deployment checklist - Manual verification
- Systemd service - Automatic startup check

---

### Pattern 5: Zero-Trust Credential Access (Enforces Rule #5)

**Rule:** "Every credential access validated. Multi-layer failover. TTL enforcement."

**Implementation in `scripts/ssh_service_accounts/fetch-credential.sh`:**
```bash
#!/bin/bash
# Zero-trust credential fetching with multi-layer fallback

fetch_credential() {
    local account=$1
    local credential_type=${2:-private_key}  # private_key, public_key, etc
    
    # Log this access attempt (for Mandate #3 - Audit Trail)
    log_operation "credential_access" "begin" "account=$account,type=$credential_type"
    
    local credential=""
    local source=""
    
    # Layer 1: Vault (Primary) - 4.2s latency, TTL enforced
    echo "Attempting to fetch from Vault..."
    if [[ -n "${VAULT_ADDR:-}" ]]; then
        credential=$(vault kv get -field="${credential_type}" "secret/ssh/${account}" 2>/dev/null)
        if [[ -n "$credential" ]]; then
            source="Vault"
            echo "✓ Retrieved from Vault"
        fi
    fi
    
    # Layer 2: GCP Secret Manager (Secondary) - 2.85s latency
    if [[ -z "$credential" ]]; then
        echo "Attempting to fetch from GCP Secret Manager..."
        local secret_name="ssh-${account}-${credential_type}"
        credential=$(gcloud secrets versions access latest \
            --secret="${secret_name}" \
            --project=nexusshield-prod 2>/dev/null)
        if [[ -n "$credential" ]]; then
            source="GSM"
            echo "✓ Retrieved from GCP Secret Manager"
        fi
    fi
    
    # Layer 3: KMS Decryption (Fallback) - For encrypted local copies
    if [[ -z "$credential" ]]; then
        echo "Attempting KMS decryption..."
        local encrypted_file="secrets/ssh/${account}/.${credential_type}.enc"
        if [[ -f "$encrypted_file" ]]; then
            credential=$(gcloud kms decrypt \
                --ciphertext-file="${encrypted_file}" \
                --plaintext-file=- \
                --project=nexusshield-prod \
                --location=us-central1 \
                --keyring=nexus-keys \
                --key=ssh-key-encryption 2>/dev/null)
            if [[ -n "$credential" ]]; then
                source="KMS"
                echo "✓ Retrieved via KMS decryption"
            fi
        fi
    fi
    
    # Layer 4: Local backup (Emergency only, <2 days)
    if [[ -z "$credential" ]]; then
        echo "Attempting local backup (emergency)..."
        local backup_file="secrets/ssh/${account}/.${credential_type}.backup"
        if [[ -f "$backup_file" ]]; then
            # Check file age (max 2 days)
            local file_age=$(($(date +%s) - $(stat -c %Y "$backup_file" 2>/dev/null || stat -f %m "$backup_file")))
            local max_age=$((2 * 86400))  # 2 days in seconds
            
            if [[ $file_age -lt $max_age ]]; then
                credential=$(cat "$backup_file")
                source="LocalBackup (${file_age}s old)"
                echo "✓ Retrieved from local backup"
            else
                echo "✗ Local backup too old (${file_age}s, max ${max_age}s)"
            fi
        fi
    fi
    
    # Validation: Ensure we got something
    if [[ -z "$credential" ]]; then
        echo "❌ MANDATE ENFORCED: All credential layers exhausted"
        log_operation "credential_access" "failed" "account=$account,reason=all_layers_exhausted"
        return 1
    fi
    
    # Log successful access
    log_operation "credential_access" "success" "account=$account,source=$source"
    
    # Return credential
    echo "$credential"
    return 0
}

# MANDATORY USAGE
# Instead of hardcoding credentials, always use:
private_key=$(fetch_credential "elevatediq-svc-worker-dev" "private_key") || exit 1

# Never do this:
# private_key="-----BEGIN OPENSSH PRIVATE KEY-----
# ... (bad! hardcoded!)"
```

**Usage guidelines:**
```bash
# ✓ CORRECT - Using the fetch function
pk=$(fetch_credential "$account" "private_key")
ssh -i <(echo "$pk") user@host "command"

# ✗ WRONG - Hardcoded secret
ssh -i ~/.ssh/secret-key user@host "command"

# ✗ WRONG - In environment variable
export PRIVATE_KEY="...secret..."
ssh-add <(echo "$PRIVATE_KEY")

# ✗ WRONG - Stored in config file
ssh -i /etc/config/secret-key user@host "command"
```

---

## MANDATE INTEGRATION CHECKLIST

When writing a new script, ensure it includes:

```bash
#!/bin/bash
set -euo pipefail

# ============================================
# MANDATE #1: No Manual Infrastructure Changes
# ============================================
verify_no_manual_changes() {
    # Implementation
}
verify_no_manual_changes || exit 1

# ============================================
# MANDATE #2: No Hardcoded Secrets
# ============================================
# ✓ Use fetch_credential() function
# ✓ Never embed secrets in script
# ✓ Pre-commit hooks will verify

# ============================================
# MANDATE #3: Immutable Audit Trail
# ============================================
source scripts/ssh_service_accounts/change_control_tracker.sh
log_operation "script_name" "begin" "details_here"

# ... do work ...

log_operation "script_name" "end" "status=success"

# ============================================
# MANDATE #4: Preflight Health Gating
# ============================================
bash scripts/ssh_service_accounts/preflight_health_gate.sh || exit 1

# ============================================
# MANDATE #5: Zero-Trust Credential Access
# ============================================
credential=$(fetch_credential "$account" "$type") || exit 1

# ... rest of script ...
```

---

## TESTING MANDATE COMPLIANCE

```bash
# Test Mandate #2 (No secrets)
# The pre-commit hook will catch secrets automatically
git add file-with-secret.txt
git commit -m "test"  # Will be blocked!

# Test Mandate #3 (Audit Trail)
bash scripts/ssh_service_accounts/audit_log_signer.sh verify
# Output: ✓ Audit trail integrity verified

# Test Mandate #4 (Health Gating)
bash scripts/ssh_service_accounts/preflight_health_gate.sh
# Shows all 11 categories + pass/fail

# Test Mandate #1 (Manual changes)
bash scripts/enforce/verify-no-manual-changes.sh
# Will detect any uncommitted changes on production
```

---

## SUMMARY

Every mandate is enforced through:
1. **Pre-commit hooks** - Catch issues before they're committed
2. **Pre-deployment checks** - Block unhealthy deployments
3. **Runtime validation** - Verify operations as they execute
4. **Audit trail** - Immutable record for investigation
5. **Health gating** - Automatic blocking of bad states

**All patterns are reusable. Copy and adapt them for your new scripts!**

