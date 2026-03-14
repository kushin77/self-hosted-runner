#!/usr/bin/env python3

"""
Create/Update GitHub issues for NexusShield on-premises infrastructure

This script:
1. Creates issues for on-prem deployment setup
2. Tracks secret management implementation
3. Documents direct deployment progress
4. Assigns milestones and labels
"""

import os
import sys
import json
import subprocess
from datetime import datetime, timedelta

# GitHub API settings
GITHUB_OWNER = "kushin77"
GITHUB_REPO = "self-hosted-runner"
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN")
API_BASE = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}"

def run_gh_command(cmd):
    """Run GitHub CLI command"""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error: {e.stderr}")
        return None

def create_issue(title, body, labels=None, milestone=None):
    """Create a GitHub issue"""
    labels = labels or []
    
    cmd = f'gh issue create --repo {GITHUB_OWNER}/{GITHUB_REPO} --title "{title}" --body "{body}"'
    
    if labels:
        cmd += " --label " + ",".join(labels)
    
    print(f"Creating issue: {title}")
    result = run_gh_command(cmd)
    
    if result:
        issue_num = result.split("/")[-1]
        print(f"✓ Created issue #{issue_num}")
        return issue_num
    return None

def close_issue(issue_num, reason="replaced"):
    """Close a GitHub issue"""
    cmd = f'gh issue close {issue_num} --repo {GITHUB_OWNER}/{GITHUB_REPO} --comment "This issue has been {reason}. See new on-premises deployment infrastructure in /infrastructure/."'
    
    run_gh_command(cmd)
    print(f"✓ Closed issue #{issue_num}")

# Issues configuration
ISSUES = [
    {
        "title": "Infrastructure: On-Premises Dedicated Host (.42)",
        "body": """## On-Premises Dedicated Infrastructure

Establish 192.168.168.42 as dedicated project infrastructure host.

### Requirements
- [ ] Host configuration complete
- [ ] Kubernetes cluster initialized
- [ ] Node labels applied (project=nexusshield, region=onprem)
- [ ] Network policies enforced
- [ ] Immutable audit trail active
- [ ] No mutable state on host (all in volumes/secrets)

### Constraints
- NEVER install on 192.168.168.31 (development)
- ONLY on 192.168.168.42 (dedicated production)
- Cloud: Secrets only (no workloads)

### Deliverables
- [x] infrastructure/on-prem-dedicated-host.sh
- [ ] Kubernetes cluster deployed to .42
- [ ] Node labels verified
- [ ] Network policies active
- [ ] Health checks passing

### Automation
- [ ] Systemd service: nexusshield-auto-deploy
- [ ] Continuous deployment loop running
- [ ] Auto-recovery on failure
- [ ] Immutable audit trail running

See: /infrastructure/on-prem-dedicated-host.sh""",
        "labels": ["infrastructure", "on-premises", "priority-critical"],
    },
    {
        "title": "Security: Secret Management (GSM/Vault/KMS)",
        "body": """## Implement Secret Management

All credentials must be managed via cloud providers (no local storage).

### Secret Providers (Vault-Primary Hierarchy)
1. Vault (on-prem, primary) - /secrets
2. GSM (GCP, secondary) - Google Secrets Manager
3. AWS Secrets Manager (tertiary)
4. Azure Key Vault (quaternary)

### Requirements
- [ ] Kubernetes service account created
- [ ] GSM integration configured (no plaintext credentials)
- [ ] Vault integration configured (API access)
- [ ] Secret injection at pod startup
- [ ] No secrets stored in git
- [ ] No secrets cached on disk > 5 minutes
- [ ] Regular rotation enabled (30-day cycle)

### Implementation
- [ ] /etc/nexusshield/secrets-config.yaml created
- [ ] Kubernetes RBAC configured
- [ ] Secret provider clients installed
- [ ] Rotation automation running
- [ ] Audit logging for all secret access
- [ ] Immutable audit trail (append-only)

### Testing
- [ ] Create test secret in GSM
- [ ] Deploy pod with auto-injection
- [ ] Verify secret accessible (not cached)
- [ ] Verify rotation works
- [ ] Verify audit logged

See: /infrastructure/on-prem-dedicated-host.sh (init_secret_management)""",
        "labels": ["security", "secrets", "priority-critical"],
    },
    {
        "title": "Automation: Direct Deployment (No GitHub Actions)",
        "body": """## Replace GitHub Actions with Direct Deployment

Remove all GitHub Actions workflows. Use direct deployment to on-prem host.

### GitHub Actions Removal
- [ ] Remove all .github/workflows/ files
- [ ] Remove GitHub Actions configuration
- [ ] Create deprecation notice
- [ ] Update CI/CD documentation

### Direct Deployment Implementation
- [ ] /usr/local/bin/nexus-deploy-direct.sh installed
- [ ] Idempotent deployment framework working
- [ ] Multi-run safety guaranteed (no double-deployments)
- [ ] Secrets injection at deploy time (not stored)
- [ ] Health checks after deployment

### Continuous Deployment Loop
- [ ] systemd service: nexusshield-auto-deploy
- [ ] Auto-fetches main branch every 5 min
- [ ] Auto-deploys on code changes
- [ ] Self-healing on failure
- [ ] Immutable audit trail

### Verification
- [ ] git push main → deployment on .42 < 5min
- [ ] No GitHub Actions triggered
- [ ] No manual approval required
- [ ] Rollback via git revert (automatic)

See: infrastructure/remove-github-actions.sh""",
        "labels": ["automation", "deployment", "priority-critical"],
    },
    {
        "title": "Architecture: Immutable Infrastructure",
        "body": """## Establish Immutable Infrastructure on .42

No mutable state should persist on the node. All state in volumes/secrets/cloud.

### Immutability Requirements
- [ ] No files written to host filesystem
- [ ] All config in ConfigMaps/Secrets (Kubernetes)
- [ ] Temporary files in tmpfs (memory, auto-cleaned)
- [ ] Persistent data in PersistentVolumes only
- [ ] Database backups automated (not stored on host)
- [ ] Audit trail: append-only JSON Lines files
- [ ] No direct SSH commands to modify state

### Enforcement
- [ ] Directories set to mode 555 (read-only)
- [ ] Audit file set to mode 444 (append ONLY)
- [ ] Deployment state: git-based (git is source of truth)
- [ ] Runtime state: cloud secrets + PVs
- [ ] No mutable state on node itself

### Validation
- [ ] Can delete all local files, redeploy = same state
- [ ] Immutable audit trail (impossible to tamper)
- [ ] All containers use non-root, read-only FS
- [ ] No privileged containers
- [ ] Security policies enforced""",
        "labels": ["architecture", "security", "immutability"],
    },
    {
        "title": "Operations: Ephemeral Container Strategy",
        "body": """## Implement Ephemeral Container Operations

Containers are temporary and replaceable. No local state attachment.

### Ephemeral Design
- [ ] Containers can be killed/restarted anytime
- [ ] Pod restart policy: on-failure
- [ ] No persistent application state in pods
- [ ] State injected via environment variables
- [ ] Temporary files use tmpfs (10 tmpfs)
- [ ] Graceful shutdown on SIGTERM (30s)

### Stateless Deployments
- [ ] All Deployments are stateless
- [ ] New pod replicas are identical (no initialization)
- [ ] Scaling down removed pods without notice
- [ ] Zero disruption from pod eviction

### Stateful Applications
- [ ] Only databases (PostgreSQL, Redis) are StatefulSets
- [ ] All with persistent volume claims
- [ ] Automated backups every 4 hours
- [ ] Restore tested periodically
- [ ] No reliance on single pod

### Autoscaling
- [ ] Horizontal Pod Autoscaler configured
- [ ] Min 2 replicas (no single point of failure)
- [ ] Max 10 replicas (cost control)
- [ ] Scale up aggressive (< 15s)
- [ ] Scale down conservative (5 min idle)

### Cost Optimization
- [ ] Idle pods cleaned up automatically
- [ ] Temporary pods created on-demand
- [ ] Resources limited (requests + limits)
- [ ] No resource leaks possible""",
        "labels": ["architecture", "operations", "cost-optimization"],
    },
    {
        "title": "Deployment: Idempotent Operations",
        "body": """## Implement Idempotent Deployment Framework

All deployments safe to run multiple times with identical results.

### Idempotency Requirements
- [ ] Deployments track state (deployment hash)
- [ ] Detect if already deployed
- [ ] Skip if already complete
- [ ] No double-deployments possible
- [ ] Failures don't corrupt state

### Implementation
- [ ] /usr/local/bin/nexus-deploy-idempotent.sh installed
- [ ] State directory: /var/nexusshield/state
- [ ] Deployment completion markers (.completed files)
- [ ] Concurrent safety: in-progress locks (.in-progress)
- [ ] Automatic cleanup on success

### Safe Operations
- [ ] kubectl apply (not create) - idempotent
- [ ] docker-compose up (not run) - idempotent
- [ ] Terraform apply (detects no-op) - idempotent
- [ ] Configuration updates (no harm if re-applied)
- [ ] Database migrations (safe re-run)

### Verification
- [ ] Run deployment 10x → same result
- [ ] Manual fixes not needed
- [ ] Health checks validate success
- [ ] No orphaned resources

### Testing
- [ ] Test deployment multiple times
- [ ] Test partial failures (then retry)
- [ ] Test concurrent deployments (safety guaranteed)
- [ ] Test rollback via git revert""",
        "labels": ["architecture", "testing", "automation"],
    },
    {
        "title": "Documentation: On-Premises Architecture Guide",
        "body": """## Create Comprehensive Architecture Documentation

Document the on-premises infrastructure for operators and developers.

### Required Documentation
- [ ] Architecture diagram (.42 as dedicated host)
- [ ] Network topology (on-prem + cloud secrets)
- [ ] Secrets flow (resolution chain)
- [ ] Deployment process (direct, no GitHub Actions)
- [ ] Runbook: Deploy to production
- [ ] Runbook: Emergency rollback
- [ ] Runbook: Scale horizontally
- [ ] Troubleshooting guide

### Diagrams
- [ ] Network topology (.31, .42, cloud)
- [ ] Secret provider resolution chain
- [ ] Deployment flow (git → .42)
- [ ] Pod lifecycle (ephemeral)
- [ ] State flow (immutable)

### Operational Guides
- [ ] How to deploy an update
- [ ] How to rollback
- [ ] How to add a new secret
- [ ] How to scale services
- [ ] How to monitor health
- [ ] How to investigate failures
- [ ] Emergency procedures

### Developer Guides  
- [ ] Local development setup
- [ ] Integration testing
- [ ] Secret access in development
- [ ] Debugging on .42
- [ ] Contributing guidelines

See: DEPLOYMENT_CONSTRAINTS_REMEDIATION.md + new docs""",
        "labels": ["documentation", "operations", "help-wanted"],
    },
]

def main():
    """Create all issues"""
    print("╔══════════════════════════════════════════════════════════╗")
    print("║      Creating GitHub Issues for On-Premises Setup        ║")
    print("╚══════════════════════════════════════════════════════════╝")
    print()
    
    if not GITHUB_TOKEN and not os.path.exists(os.path.expanduser("~/.config/gh/hosts.yml")):
        print("Error: GitHub token not found.")
        print("Set GITHUB_TOKEN env var or run: gh auth login")
        sys.exit(1)
    
    created_issues = []
    for issue_config in ISSUES:
        issue_num = create_issue(
            issue_config["title"],
            issue_config["body"],
            labels=issue_config.get("labels", [])
        )
        if issue_num:
            created_issues.append(issue_num)
    
    print()
    print("╔══════════════════════════════════════════════════════════╗")
    print(f"║   ✅ Created {len(created_issues)} GitHub Issues                      ║")
    print("║                                                          ║")
    print("║   Infrastructure Tracking:                              ║")
    for i, issue_num in enumerate(created_issues, 1):
        print(f"║   {i}. GitHub Issue #{issue_num}                         ║")
    print("║                                                          ║")
    print("║   Next: Start closing issues as work completes           ║")
    print("╚══════════════════════════════════════════════════════════╝")

if __name__ == "__main__":
    main()
