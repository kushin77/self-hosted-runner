#!/usr/bin/env python3
"""
À la carte deployment orchestration framework.

This package provides modular, selective deployment of infrastructure components
with immutable audit logging, credential injection (GSM/Vault/KMS), and GitHub
issue automation.

Modules:
- components: Component registry and definitions
- alacarte: Core orchestration engine
- github_automation: GitHub issue automation

Usage:
    from deployment.alacarte import DeploymentOrchestrator
    
    orchestrator = DeploymentOrchestrator()
    success = orchestrator.deploy_components([
        "remove-embedded-secrets",
        "migrate-to-gsm",
        "setup-credential-rotation"
    ])

Architecture:
- Immutable: All deployments logged to append-only audit trail
- Idempotent: Safe to re-run deployments (no duplicate side effects)
- Ephemeral: Temporary files auto-cleaned
- No-Ops: Fully automated, hands-off execution
- Secure: Credentials injected via GSM/Vault/KMS with OIDC/WIF
"""

__version__ = "1.0.0"
__author__ = "Akushnir"

from deployment.components import (
    ComponentStatus,
    ComponentCredential,
    ComponentStep,
    DeploymentComponent,
    get_component,
    list_components,
    get_deployment_order,
)

from deployment.alacarte import (
    DeploymentAudit,
    CredentialInjector,
    DeploymentOrchestrator,
)

from deployment.github_automation import (
    GitHubIssueAutomation,
    GitHubIssueTracker,
)

__all__ = [
    # Components
    "ComponentStatus",
    "ComponentCredential",
    "ComponentStep",
    "DeploymentComponent",
    "get_component",
    "list_components",
    "get_deployment_order",
    
    # Orchestration
    "DeploymentAudit",
    "CredentialInjector",
    "DeploymentOrchestrator",
    
    # GitHub Automation
    "GitHubIssueAutomation",
    "GitHubIssueTracker",
]
