#!/usr/bin/env python3
"""
À la carte deployment components registry.

Defines all deployable components with their:
- Dependencies (what must run before)
- Execution steps
- Credential requirements
- GitHub issue tracking
- Success validation
"""

import os
from dataclasses import dataclass, field
from typing import Dict, List, Callable, Optional, Any
from enum import Enum
import json


class ComponentStatus(Enum):
    """Component deployment status."""
    PENDING = "pending"
    IN_PROGRESS = "in-progress"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass
class ComponentCredential:
    """Credential requirement for a component."""
    name: str
    credential_type: str  # 'gsm', 'vault', 'kms', 'oidc', 'wif'
    secret_name: str
    required: bool = True


@dataclass
class ComponentStep:
    """Single execution step for a component."""
    name: str
    description: str
    command: str
    working_dir: str = "/home/akushnir/self-hosted-runner"
    timeout_seconds: int = 300
    retry_count: int = 3
    continue_on_error: bool = False


@dataclass
class DeploymentComponent:
    """À la carte deployable component."""
    
    # Identity
    component_id: str
    name: str
    category: str  # 'security', 'credential', 'automation', 'healing', 'monitoring'
    version: str
    
    # Metadata
    description: str
    documentation_url: str = ""
    
    # Execution
    steps: List[ComponentStep] = field(default_factory=list)
    dependencies: List[str] = field(default_factory=list)  # Component IDs
    
    # Credentials
    credentials: List[ComponentCredential] = field(default_factory=list)
    
    # GitHub Tracking
    github_issue_template: str = ""
    github_labels: List[str] = field(default_factory=list)
    
    # Validation
    validation_steps: List[ComponentStep] = field(default_factory=list)
    
    # Properties
    auto_remediate: bool = False
    is_critical: bool = False
    can_rollback: bool = False
    
    def __post_init__(self):
        """Validate component configuration."""
        if not self.component_id:
            raise ValueError("component_id is required")
        if not self.steps:
            raise ValueError(f"Component {self.component_id} has no execution steps")


# ═══════════════════════════════════════════════════════════════════════════════
# COMPONENT REGISTRY - All deployable components
# ═══════════════════════════════════════════════════════════════════════════════

COMPONENTS_REGISTRY: Dict[str, DeploymentComponent] = {
    
    # ───────────────────────────────────────────────────────────────────────────
    # SECURITY: Secret Remediation
    # ───────────────────────────────────────────────────────────────────────────
    
    "remove-embedded-secrets": DeploymentComponent(
        component_id="remove-embedded-secrets",
        name="Remove Embedded Secrets",
        category="security",
        version="1.0.0",
        description="Scan and remove hardcoded secrets from repository history",
        github_labels=["security", "remediation"],
        is_critical=True,
        steps=[
            ComponentStep(
                name="scan-repo-secrets",
                description="Scan repository for embedded secrets",
                command="python3 scripts/security/scan_secrets.py --full-scan --output scan-results.json",
                timeout_seconds=600,
                retry_count=1
            ),
            ComponentStep(
                name="remove-secrets",
                description="Remove secrets from git history",
                command="python3 scripts/security/remove_secrets.py --confirm --audit-trail",
                timeout_seconds=300,
                continue_on_error=False
            ),
            ComponentStep(
                name="verify-removal",
                description="Verify all secrets have been removed",
                command="python3 scripts/security/verify_secrets_removed.py --strict",
                timeout_seconds=300
            ),
        ],
        credentials=[
            ComponentCredential(name="github_token", credential_type="oidc", secret_name="GITHUB_TOKEN"),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-no-secrets",
                description="Validate no secrets remain in repository",
                command="python3 scripts/security/validate_no_secrets.py --fail-on-match",
                timeout_seconds=300
            ),
        ],
        github_issue_template="SECURITY_REMEDIATION",
    ),
    
    # ───────────────────────────────────────────────────────────────────────────
    # CREDENTIALS: Secret Migration to GSM/Vault/KMS
    # ───────────────────────────────────────────────────────────────────────────
    
    "migrate-to-gsm": DeploymentComponent(
        component_id="migrate-to-gsm",
        name="Migrate Secrets to Google Secret Manager",
        category="credential",
        version="1.0.0",
        description="Migrate repository secrets to Google Secret Manager with OIDC integration",
        dependencies=["remove-embedded-secrets"],
        github_labels=["security", "credentials", "gsm"],
        is_critical=True,
        steps=[
            ComponentStep(
                name="inventory-secrets",
                description="Inventory all repository and org secrets",
                command="python3 scripts/credentials/inventory_secrets.py --output secrets-inventory.json",
                timeout_seconds=300
            ),
            ComponentStep(
                name="setup-gsm",
                description="Setup Google Secret Manager project",
                command="bash scripts/credentials/setup_gsm.sh",
                timeout_seconds=600,
                continue_on_error=False
            ),
            ComponentStep(
                name="migrate-secrets",
                description="Migrate secrets to GSM",
                command="python3 scripts/credentials/migrate_to_gsm.py --inventory secrets-inventory.json --confirm",
                timeout_seconds=600,
                retry_count=2
            ),
            ComponentStep(
                name="setup-oidc",
                description="Configure OIDC for GSM access",
                command="bash scripts/credentials/setup_gsm_oidc.sh",
                timeout_seconds=300
            ),
        ],
        credentials=[
            ComponentCredential(name="gcp_project_id", credential_type="gsm", secret_name="GCP_PROJECT_ID"),
            ComponentCredential(name="github_token", credential_type="oidc", secret_name="GITHUB_TOKEN"),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-gsm-access",
                description="Validate GSM access via OIDC",
                command="python3 scripts/credentials/validate_gsm_oidc.py",
                timeout_seconds=300
            ),
        ],
        github_issue_template="CREDENTIAL_MIGRATION",
    ),
    
    "migrate-to-vault": DeploymentComponent(
        component_id="migrate-to-vault",
        name="Migrate Secrets to HashiCorp Vault",
        category="credential",
        version="1.0.0",
        description="Migrate repository secrets to HashiCorp Vault with JWT auth",
        dependencies=["remove-embedded-secrets"],
        github_labels=["security", "credentials", "vault"],
        is_critical=True,
        steps=[
            ComponentStep(
                name="inventory-secrets",
                description="Inventory all repository and org secrets",
                command="python3 scripts/credentials/inventory_secrets.py --output secrets-inventory.json",
                timeout_seconds=300
            ),
            ComponentStep(
                name="setup-vault",
                description="Setup HashiCorp Vault authentication",
                command="bash scripts/credentials/setup_vault.sh",
                timeout_seconds=600,
                continue_on_error=False
            ),
            ComponentStep(
                name="migrate-secrets",
                description="Migrate secrets to Vault",
                command="python3 scripts/credentials/migrate_to_vault.py --inventory secrets-inventory.json --confirm",
                timeout_seconds=600,
                retry_count=2
            ),
            ComponentStep(
                name="setup-jwt-auth",
                description="Configure JWT auth for Vault",
                command="bash scripts/credentials/setup_vault_jwt_auth.sh",
                timeout_seconds=300
            ),
        ],
        credentials=[
            ComponentCredential(name="vault_addr", credential_type="vault", secret_name="VAULT_ADDR"),
            ComponentCredential(name="vault_token", credential_type="vault", secret_name="VAULT_TOKEN"),
            ComponentCredential(name="github_token", credential_type="oidc", secret_name="GITHUB_TOKEN"),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-vault-access",
                description="Validate Vault access via JWT",
                command="python3 scripts/credentials/validate_vault_jwt.py",
                timeout_seconds=300
            ),
        ],
        github_issue_template="CREDENTIAL_MIGRATION",
    ),
    
    "migrate-to-kms": DeploymentComponent(
        component_id="migrate-to-kms",
        name="Migrate Secrets to AWS KMS",
        category="credential",
        version="1.0.0",
        description="Migrate repository secrets to AWS KMS with WIF integration",
        dependencies=["remove-embedded-secrets"],
        github_labels=["security", "credentials", "kms", "aws"],
        is_critical=True,
        steps=[
            ComponentStep(
                name="inventory-secrets",
                description="Inventory all repository and org secrets",
                command="python3 scripts/credentials/inventory_secrets.py --output secrets-inventory.json",
                timeout_seconds=300
            ),
            ComponentStep(
                name="setup-aws-kms",
                description="Setup AWS KMS and OIDC provider",
                command="bash scripts/credentials/setup_aws_kms.sh",
                timeout_seconds=600,
                continue_on_error=False
            ),
            ComponentStep(
                name="migrate-secrets",
                description="Migrate secrets to AWS KMS",
                command="python3 scripts/credentials/migrate_to_kms.py --inventory secrets-inventory.json --confirm",
                timeout_seconds=600,
                retry_count=2
            ),
            ComponentStep(
                name="setup-wif",
                description="Configure Workload Identity Federation",
                command="bash scripts/credentials/setup_aws_wif.sh",
                timeout_seconds=300
            ),
        ],
        credentials=[
            ComponentCredential(name="aws_account_id", credential_type="kms", secret_name="AWS_ACCOUNT_ID"),
            ComponentCredential(name="aws_region", credential_type="kms", secret_name="AWS_REGION"),
            ComponentCredential(name="github_token", credential_type="oidc", secret_name="GITHUB_TOKEN"),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-aws-kms-access",
                description="Validate AWS KMS access via WIF",
                command="python3 scripts/credentials/validate_aws_kms_wif.py",
                timeout_seconds=300
            ),
        ],
        github_issue_template="CREDENTIAL_MIGRATION",
    ),
    
    # ───────────────────────────────────────────────────────────────────────────
    # AUTOMATION: Dynamic Credential Retrieval
    # ───────────────────────────────────────────────────────────────────────────
    
    "setup-dynamic-credential-retrieval": DeploymentComponent(
        component_id="setup-dynamic-credential-retrieval",
        name="Setup Dynamic Credential Retrieval",
        category="automation",
        version="1.0.0",
        description="Configure dynamic credential retrieval helpers for workflows",
        dependencies=["migrate-to-gsm", "migrate-to-vault", "migrate-to-kms"],
        github_labels=["automation", "credentials"],
        is_critical=True,
        steps=[
            ComponentStep(
                name="create-retrieval-actions",
                description="Create GitHub Actions for credential retrieval",
                command="bash scripts/automation/create_credential_actions.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="create-retrieval-scripts",
                description="Create credential retrieval scripts",
                command="bash scripts/automation/create_retrieval_scripts.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="update-workflows",
                description="Update all workflows to use dynamic retrieval",
                command="python3 scripts/automation/update_workflows_dynamic_retrieval.py --confirm",
                timeout_seconds=600
            ),
            ComponentStep(
                name="test-retrieval",
                description="Test dynamic credential retrieval",
                command="python3 scripts/automation/test_credential_retrieval.py",
                timeout_seconds=300
            ),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-dynamic-retrieval",
                description="Validate all workflows use dynamic retrieval",
                command="python3 scripts/automation/validate_dynamic_retrieval.py --strict",
                timeout_seconds=300
            ),
        ],
        github_issue_template="AUTOMATION_SETUP",
    ),
    
    # ───────────────────────────────────────────────────────────────────────────
    # AUTOMATION: Credential Rotation
    # ───────────────────────────────────────────────────────────────────────────
    
    "setup-credential-rotation": DeploymentComponent(
        component_id="setup-credential-rotation",
        name="Setup Automated Credential Rotation",
        category="automation",
        version="1.0.0",
        description="Setup automated credential rotation workflows",
        dependencies=["setup-dynamic-credential-retrieval"],
        github_labels=["automation", "credentials", "rotation"],
        is_critical=True,
        auto_remediate=True,
        steps=[
            ComponentStep(
                name="create-rotation-workflows",
                description="Create credential rotation workflows",
                command="bash scripts/automation/create_rotation_workflows.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="schedule-rotation",
                description="Schedule automatic credential rotation",
                command="python3 scripts/automation/schedule_rotation.py --daily --time 02:00",
                timeout_seconds=300
            ),
            ComponentStep(
                name="setup-audit-logging",
                description="Setup audit logging for rotations",
                command="bash scripts/automation/setup_rotation_audit_logging.sh",
                timeout_seconds=300
            ),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-rotation-schedule",
                description="Validate rotation workflows are scheduled",
                command="python3 scripts/automation/validate_rotation_schedule.py",
                timeout_seconds=300
            ),
        ],
        github_issue_template="AUTOMATION_SETUP",
    ),
    
    # ───────────────────────────────────────────────────────────────────────────
    # HEALING: RCA-driven Auto-Healer (Already Deployed)
    # ───────────────────────────────────────────────────────────────────────────
    
    "activate-rca-autohealer": DeploymentComponent(
        component_id="activate-rca-autohealer",
        name="Activate RCA-Driven Auto-Healer",
        category="healing",
        version="2.0.0",
        description="Activate RCA-driven auto-healer for workflow failure recovery",
        github_labels=["healing", "rca", "production"],
        auto_remediate=True,
        steps=[
            ComponentStep(
                name="verify-rca-module",
                description="Verify RCA module is deployed",
                command="python3 -c 'from self_healing.rca import WorkflowFailureAnalyzer; print(\"✅ RCA module verified\")'",
                timeout_seconds=60
            ),
            ComponentStep(
                name="verify-enhanced-healer",
                description="Verify enhanced healer module is deployed",
                command="python3 -c 'from self_healing.enhanced_healer import RemediationOrchestrator; print(\"✅ Enhanced healer verified\")'",
                timeout_seconds=60
            ),
            ComponentStep(
                name="activate-monitoring",
                description="Activate workflow failure monitoring",
                command="python3 -c 'from self_healing.enhanced_healer import WorkflowFailureMonitor; print(\"✅ Monitoring activated\")'",
                timeout_seconds=60
            ),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-rca-active",
                description="Validate RCA system is active",
                command="python3 scripts/healing/validate_rca_active.py",
                timeout_seconds=300
            ),
        ],
        github_issue_template="HEALING_ACTIVATION",
    ),
    
    # ───────────────────────────────────────────────────────────────────────────
    # PHASE 3: KEY REVOCATION & CREDENTIAL REGENERATION
    # ───────────────────────────────────────────────────────────────────────────
    
    "revoke-exposed-keys": DeploymentComponent(
        component_id="revoke-exposed-keys",
        name="Revoke Exposed & Compromised Keys",
        category="security",
        version="1.0.0",
        description="Scan for and revoke all exposed keys across all systems",
        dependencies=["remove-embedded-secrets"],
        github_labels=["security", "remediation", "phase-3"],
        is_critical=True,
        steps=[
            ComponentStep(
                name="scan-exposed-keys",
                description="Scan repository for exposed keys using gitleaks/truffleHog",
                command="bash scripts/security/scan_exposed_keys.sh",
                timeout_seconds=600,
                retry_count=1
            ),
            ComponentStep(
                name="revoke-github-tokens",
                description="Revoke exposed GitHub tokens",
                command="bash scripts/security/revoke_github_tokens.sh --confirm",
                timeout_seconds=300,
                retry_count=1
            ),
            ComponentStep(
                name="revoke-gcp-keys",
                description="Revoke exposed GCP service account keys",
                command="bash scripts/security/revoke_gcp_keys.sh",
                timeout_seconds=300,
                retry_count=1
            ),
            ComponentStep(
                name="revoke-aws-keys",
                description="Revoke exposed AWS IAM user keys",
                command="bash scripts/security/revoke_aws_keys.sh",
                timeout_seconds=300,
                retry_count=1
            ),
            ComponentStep(
                name="revoke-vault-tokens",
                description="Revoke exposed Vault tokens",
                command="bash scripts/security/revoke_vault_tokens.sh",
                timeout_seconds=300,
                retry_count=1
            ),
            ComponentStep(
                name="document-revocations",
                description="Document all revocations in immutable audit log",
                command="bash scripts/security/document_revocations.sh --audit-trail",
                timeout_seconds=300
            ),
        ],
        credentials=[
            ComponentCredential(name="github_token", credential_type="oidc", secret_name="GITHUB_TOKEN"),
            ComponentCredential(name="gcp_project_id", credential_type="gsm", secret_name="GCP_PROJECT_ID"),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-revocations",
                description="Validate all keys have been revoked",
                command="bash scripts/security/validate_revocations.sh --strict",
                timeout_seconds=300
            ),
        ],
        github_issue_template="SECURITY_REMEDIATION",
    ),
    
    "regenerate-credentials": DeploymentComponent(
        component_id="regenerate-credentials",
        name="Regenerate All Fresh Credentials",
        category="security",
        version="1.0.0",
        description="Create fresh credentials for all systems post-revocation",
        dependencies=["revoke-exposed-keys"],
        github_labels=["security", "credentials", "phase-3"],
        is_critical=True,
        steps=[
            ComponentStep(
                name="generate-github-token",
                description="Generate new GitHub PAT token",
                command="bash scripts/security/generate_github_token.sh --scope minimal --confirm",
                timeout_seconds=300
            ),
            ComponentStep(
                name="generate-gcp-keys",
                description="Generate new GCP service account keys",
                command="bash scripts/security/generate_gcp_keys.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="generate-aws-keys",
                description="Generate new AWS IAM user keys",
                command="bash scripts/security/generate_aws_keys.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="generate-vault-tokens",
                description="Generate new Vault tokens",
                command="bash scripts/security/generate_vault_tokens.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="update-github-secrets",
                description="Update GitHub Secrets with new credentials",
                command="bash scripts/security/update_secrets.sh --new-credentials --confirm",
                timeout_seconds=300
            ),
            ComponentStep(
                name="document-regeneration",
                description="Document credential regeneration",
                command="bash scripts/security/document_regeneration.sh --audit-trail",
                timeout_seconds=300
            ),
        ],
        credentials=[
            ComponentCredential(name="github_token", credential_type="oidc", secret_name="GITHUB_TOKEN"),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-new-credentials",
                description="Validate all new credentials are working",
                command="bash scripts/security/validate_new_credentials.sh --strict",
                timeout_seconds=300
            ),
        ],
        github_issue_template="SECURITY_REMEDIATION",
    ),
    
    "verify-health": DeploymentComponent(
        component_id="verify-health",
        name="Verify All Layers Post-Remediation",
        category="security",
        version="1.0.0",
        description="Verify all credential layers are healthy after revocation/regeneration",
        dependencies=["regenerate-credentials"],
        github_labels=["security", "validation", "phase-3"],
        is_critical=True,
        steps=[
            ComponentStep(
                name="verify-gsm-access",
                description="Verify GSM access is working",
                command="bash scripts/security/verify_gsm_access.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="verify-vault-access",
                description="Verify Vault JWT access is working",
                command="bash scripts/security/verify_vault_access.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="verify-aws-access",
                description="Verify AWS STS token access is working",
                command="bash scripts/security/verify_aws_access.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="verify-workflows",
                description="Verify all workflows can fetch credentials",
                command="bash scripts/security/verify_workflow_access.sh --all",
                timeout_seconds=600
            ),
            ComponentStep(
                name="final-validation",
                description="Final comprehensive health check",
                command="bash scripts/security/final_health_check.sh",
                timeout_seconds=300
            ),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-all-healthy",
                description="Validate all layers are operational",
                command="bash scripts/security/validate_all_health.sh --strict",
                timeout_seconds=300
            ),
        ],
        github_issue_template="VALIDATION",
    ),
    
    # ───────────────────────────────────────────────────────────────────────────
    # PHASE 4: PRODUCTION VALIDATION
    # ───────────────────────────────────────────────────────────────────────────
    
    "setup-production-monitoring": DeploymentComponent(
        component_id="setup-production-monitoring",
        name="Setup Production Monitoring & Validation",
        category="monitoring",
        version="1.0.0",
        description="Setup continuous monitoring for production validation phase",
        dependencies=["verify-health"],
        github_labels=["monitoring", "phase-4"],
        is_critical=True,
        steps=[
            ComponentStep(
                name="deploy-auth-monitoring",
                description="Deploy authentication success rate monitoring (99.9% SLA)",
                command="bash scripts/monitoring/deploy_auth_monitoring.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="deploy-rotation-monitoring",
                description="Deploy credential rotation success monitoring (100%)",
                command="bash scripts/monitoring/deploy_rotation_monitoring.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="setup-incident-detection",
                description="Setup automatic incident detection and alerting",
                command="bash scripts/monitoring/setup_incident_detection.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="deploy-dashboards",
                description="Deploy monitoring dashboards",
                command="bash scripts/monitoring/deploy_dashboards.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="configure-alerts",
                description="Configure production alerts",
                command="bash scripts/monitoring/configure_alerts.sh",
                timeout_seconds=300
            ),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-monitoring",
                description="Validate monitoring is operational",
                command="bash scripts/monitoring/validate_monitoring.sh",
                timeout_seconds=300
            ),
        ],
        github_issue_template="MONITORING_SETUP",
    ),
    
    # ───────────────────────────────────────────────────────────────────────────
    # PHASE 5: 24/7 OPERATIONS
    # ───────────────────────────────────────────────────────────────────────────
    
    "activate-24x7-operations": DeploymentComponent(
        component_id="activate-24x7-operations",
        name="Activate 24/7 Operations & Incident Response",
        category="operations",
        version="1.0.0",
        description="Activate permanent 24/7 operations and incident response",
        dependencies=["setup-production-monitoring"],
        github_labels=["operations", "phase-5"],
        is_critical=True,
        auto_remediate=True,
        steps=[
            ComponentStep(
                name="enable-incident-response",
                description="Enable automatic incident response workflows",
                command="bash scripts/operations/enable_incident_response.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="setup-compliance-reporting",
                description="Setup daily compliance reporting",
                command="bash scripts/operations/setup_compliance_reporting.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="activate-audit-logging",
                description="Activate comprehensive audit logging",
                command="bash scripts/operations/activate_audit_logging.sh --permanent",
                timeout_seconds=300
            ),
            ComponentStep(
                name="setup-runbooks",
                description="Deploy operational runbooks",
                command="bash scripts/operations/deploy_runbooks.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="configure-escalation",
                description="Configure escalation policies and notifications",
                command="bash scripts/operations/configure_escalation.sh",
                timeout_seconds=300
            ),
            ComponentStep(
                name="final-activation",
                description="Final activation for 24/7 ops",
                command="bash scripts/operations/final_activation.sh --confirm",
                timeout_seconds=300
            ),
        ],
        validation_steps=[
            ComponentStep(
                name="validate-24x7-ready",
                description="Validate 24/7 operations are fully active",
                command="bash scripts/operations/validate_24x7_ready.sh --strict",
                timeout_seconds=300
            ),
        ],
        github_issue_template="OPERATIONS_ACTIVATION",
    ),
}


def get_component(component_id: str) -> Optional[DeploymentComponent]:
    """Get component by ID."""
    return COMPONENTS_REGISTRY.get(component_id)


def list_components(category: Optional[str] = None) -> List[DeploymentComponent]:
    """List all available components, optionally filtered by category."""
    components = list(COMPONENTS_REGISTRY.values())
    if category:
        components = [c for c in components if c.category == category]
    return components


def list_categories() -> List[str]:
    """List all component categories."""
    categories = set(c.category for c in COMPONENTS_REGISTRY.values())
    return sorted(list(categories))


def validate_component_dependencies(component_id: str, deployed_components: List[str]) -> bool:
    """Validate that all dependencies for a component are deployed."""
    component = get_component(component_id)
    if not component:
        return False
    
    for dep in component.dependencies:
        if dep not in deployed_components:
            return False
    
    return True


def get_deployment_order(component_ids: List[str]) -> List[str]:
    """
    Topological sort to determine deployment order respecting dependencies.
    Returns components in correct deployment order, or raises ValueError if circular dependency.
    """
    from collections import defaultdict, deque
    
    # Build dependency graph
    graph = defaultdict(list)
    in_degree = defaultdict(int)
    
    for comp_id in component_ids:
        component = get_component(comp_id)
        if not component:
            raise ValueError(f"Unknown component: {comp_id}")
        
        in_degree[comp_id] = len([d for d in component.dependencies if d in component_ids])
        
        for dep in component.dependencies:
            if dep in component_ids:
                graph[dep].append(comp_id)
    
    # Kahn's algorithm
    queue = deque([comp_id for comp_id in component_ids if in_degree[comp_id] == 0])
    result = []
    
    while queue:
        node = queue.popleft()
        result.append(node)
        
        for neighbor in graph[node]:
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                queue.append(neighbor)
    
    if len(result) != len(component_ids):
        raise ValueError("Circular dependency detected in component deployment")
    
    return result


if __name__ == "__main__":
    # Display registry
    print("=" * 80)
    print("À LA CARTE DEPLOYMENT COMPONENTS REGISTRY")
    print("=" * 80)
    
    for category in list_categories():
        print(f"\n[{category.upper()}]")
        for component in list_components(category):
            print(f"  • {component.component_id:<40} v{component.version:<5} - {component.name}")
            if component.dependencies:
                print(f"    Dependencies: {', '.join(component.dependencies)}")
