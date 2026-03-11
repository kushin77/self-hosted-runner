# Policy-as-Code Framework

**Status:** ✅ ACTIVE | **Version:** 1.0 | **Last Updated:** 2026-03-11

---

## 🎯 Principle

**Single Source of Truth:** Policy defined in code format → Auto-generated into:
- Git hooks (enforcement)
- RBAC rules (access control)
- Audit validators (compliance)
- CLI validators (developer ergonomics)
- Documentation (human-readable)

All derived artifacts generated deterministically from policy source.

---

## 📝 Policy Specification Language

### Capability Policy
```yaml
capability:
  id: "rotate_secrets"
  name: "Rotate Secrets (Credentials Manager)"
  description: "Create new versions of secrets in GSM/Vault/KMS"
  
  roles_allowed:
    - "CredentialManager"
    - "SecurityArchitect"
    - "Admin"
  
  rate_limit:
    max_per_minute: 2
    max_per_hour: 50
    max_per_day: 500
    window_seconds: 60
  
  resources:
    - pattern: "secret:*:credentials:*"
      backends: ["GSM", "Vault", "KMS"]
    - pattern: "secret:prod:*"  # prod secrets
      require_approval: true
      approvers: ["SecurityArchitect", "ComplianceOfficer"]
    - pattern: "secret:dev:*"   # dev secrets
      require_approval: false
  
  duration:
    max_seconds: 3600  # 1 hour max
    default_seconds: 1800  # 30 min default
  
  audit:
    log_full_context: true
    require_justification: true
    sensitive_fields: ["secret_value", "encryption_key"]
```

### Operation Policy
```yaml
operation:
  id: "deploy_to_production"
  name: "Deploy to Production"
  description: "Deploy code/infra to production environment"
  
  requires_approvals: 2
  approval_roles:
    - "DeploymentEngineer"
    - "ComplianceOfficer"
  
  prerequisites:
    - check: "staging_tests_passed"
      severity: "HARD_STOP"
    - check: "security_scan_passed"
      severity: "HARD_STOP"
    - check: "compliance_audit_ok"
      severity: "HARD_STOP"
```

### Governance Rule
```yaml
governance:
  id: "no_github_actions"
  name: "No GitHub Actions"
  description: "GitHub Actions disabled; only direct deployment via SSH"
  
  enforcement:
    - type: "git_hook"
      hook_name: "prevent-workflows"
      trigger: "commit"
      action: "BLOCK"
      message: "GitHub Actions workflows not allowed"
    
    - type: "policy_check"
      when: "file_modified"
      pattern: ".github/workflows/*"
      action: "PREVENT_MERGE"
```

---

## 🔄 Code Generation Pipeline

```
policies/
├── capabilities.yaml       # Capability definitions
├── operations.yaml         # Operation flows
└── governance.yaml         # Governance rules
    ↓
[Policy Compiler]
    ↓
├── .git/hooks/pre-commit              (generated)
├── .git/hooks/prevent-workflows       (generated)
├── docs/RBAC_RULES_GENERATED.yaml     (generated)
├── scripts/validators/capability-check.sh   (generated)
├── scripts/validators/operation-check.sh    (generated)
└── docs/POLICY_DOCUMENTATION.md       (generated)
```

### Generation Rules

```bash
# Policy → Git Hook
capability "rotate_secrets" + role "CredentialManager"
  → generates check in pre-commit hook: validate_actor_role()

# Policy → Documentation
capability definition + RBAC + examples
  → generates section in POLICY_DOCUMENTATION.md

# Policy → Validator
operation "deploy_to_production" + prerequisites
  → generates deploy_to_production_validate() function
```

---

## 🧪 Validation Rules Generated

### From `rotate_secrets` Capability:

```bash
# Auto-generated validation function in scripts/validators/rotate-secrets-validator.sh

validate_rotate_secrets() {
    local actor="$1"
    
    # Check 1: Role Capability
    if ! role_has_capability "$actor" "rotate_secrets"; then
        log_violation "unauthorized_rotate_secrets" "$actor"
        return 1
    fi
    
    # Check 2: Rate Limit
    local count=$(get_access_count "$actor" "rotate_secrets" "last_minute")
    if [ "$count" -ge 2 ]; then
        log_violation "rate_limit_exceeded" "$actor"
        return 1
    fi
    
    # Check 3: Approval (if prod)
    if is_prod_secret "$secret"; then
        if ! has_approval "rotate_secrets" "$secret"; then
            log_violation "missing_approval" "$actor" "$secret"
            return 1
        fi
    fi
    
    return 0
}
```

---

## 📋 Policy Versioning

```
policies/
├── v1.0/
│   ├── capabilities.yaml  (original)
│   ├── operations.yaml
│   └── governance.yaml
├── v1.1/
│   ├── capabilities.yaml  (new)
│   ├── operations.yaml
│   └── governance.yaml
└── CURRENT -> v1.1/  (symlink)

# Every change creates new version:
# - Append-only (v1.0 never modified)
# - Full audit trail (who changed what, when, why)
# - Rollback capability (can revert to any prior version)
# - Compatibility checking (old policies forward-compatible? y/n)
```

---

## 🔄 Policy Change Process

```
1. Developer writes new policy in policies/v{N+1}/
2. Policy compiler validates syntax
3. Generation runs: hooks, validators, docs all auto-generated
4. Tests run against generated artifacts
5. Security architect reviews changes
6. Compliance officer approves
7. Merge to main → symlink CURRENT updates
8. All deployments immediately use new policies
9. Old version archived in git history (immutable)
10. Audit trail: version history with approvals
```

---

## ✅ Consistency Guarantee

```
Policy Source → [Compiler] → All Artifacts
                    ↓
        Single Point of Truth

Result:
- ✅ Git hooks consistent with RBAC
- ✅ Validators consistent with docs
- ✅ Capability rules consistent across all systems
- ✅ Zero manual sync needed (generated deterministically)
- ✅ Any policy bug fixed in one place → all systems updated
```

---

## 📊 Policy Compliance Matrix

| Component | Policy | Generated? | Tested? | Verified? |
|---|---|---|---|---|
| Capability: rotate_secrets | v1.0 | ✅ | ✅ | ✅ |
| Operation: deploy_to_production | v1.0 | ✅ | ✅ | ✅ |
| Governance: no_github_actions | v1.0 | ✅ | ✅ | ✅ |
| Governance: immutable_audit | v1.0 | ✅ | ✅ | ✅ |
| Capability: view_audit_logs | v1.0 | ✅ | ✅ | ✅ |

---

## 🎯 Example: Policy Change (Immediate Deployment)

**Scenario:** Add new capability "emergency_secret_access"

```yaml
# File: policies/v1.1/capabilities.yaml
capability:
  id: "emergency_secret_access"
  name: "Emergency Secret Access"
  roles_allowed: ["Admin", "SecurityArchitect"]
  
  requires_approval: 2
  approvers: ["SecurityArchitect", "ComplianceOfficer"]
  
  duration:
    max_seconds: 300  # 5 minutes only
    emergency_override: true  # admin can override longer
```

**Automatic Results:**
1. ✅ Pre-commit hook updated (blocks un-approved access)
2. ✅ RBAC rules regenerated (role checks updated)
3. ✅ Validator function created (access validation)
4. ✅ Documentation updated (added to POLICY_DOCUMENTATION.md)
5. ✅ Tests generated (validates new capability)
6. ✅ Audit record created (who added capability, when, why)
7. ✅ All git deployments immediately enforce new policy

---

## 🔐 Anti-Patterns Prevented

```
❌ Code doesn't match documentation → Generation ensures sync
❌ Role definition differs from git hook → Single source of truth
❌ Approval requirements forgotten → Policy compiler validates
❌ Rate limits inconsistent → Centralized definition
❌ New capability unknown to validators → Auto-generated
```

---

## ✅ Compliance Certification

- ✅ Single source of truth
- ✅ Deterministic generation
- ✅ Immutable version history
- ✅ Full audit trail of changes
- ✅ Zero manual sync required
- ✅ Consistency guaranteed by architecture
