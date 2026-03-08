#!/usr/bin/env python3
"""
GitHub issue automation for deployment tracking.

Provides:
- Automatic issue creation for deployments
- Issue status updates
- Issue closure on completion
- Issue linking to deployment manifests
"""

import os
import subprocess
import json
from datetime import datetime
from typing import Dict, List, Optional, Any
import logging

logger = logging.getLogger(__name__)


class GitHubIssueAutomation:
    """Automate GitHub issue creation and management."""
    
    def __init__(self):
        self.github_token = os.environ.get("GITHUB_TOKEN")
        self.github_repo = os.environ.get("GITHUB_REPOSITORY", "kushin77/self-hosted-runner")
        self.github_owner, self.github_repo_name = self.github_repo.split("/")
    
    def create_issue(self,
                     title: str,
                     body: str,
                     labels: List[str] = None,
                     assignees: List[str] = None) -> Optional[int]:
        """Create a GitHub issue."""
        try:
            cmd = f"""gh issue create \
                --title "{title}" \
                --body "{body.replace(chr(34), chr(92) + chr(34))}" """
            
            if labels:
                cmd += f"--label {','.join(labels)} "
            
            if assignees:
                cmd += f"--assignee {','.join(assignees)} "
            
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            
            if result.returncode == 0:
                # Extract issue number from output
                output = result.stdout.strip()
                issue_number = int(output.split('/')[-1])
                logger.info(f"Created issue #{issue_number}")
                return issue_number
            else:
                logger.error(f"Failed to create issue: {result.stderr}")
                return None
        
        except Exception as e:
            logger.error(f"Error creating issue: {e}")
            return None
    
    def close_issue(self, issue_number: int) -> bool:
        """Close a GitHub issue."""
        try:
            result = subprocess.run(
                f"gh issue close {issue_number}",
                shell=True,
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                logger.info(f"Closed issue #{issue_number}")
                return True
            else:
                logger.error(f"Failed to close issue: {result.stderr}")
                return False
        except Exception as e:
            logger.error(f"Error closing issue: {e}")
            return False
    
    def update_issue(self, issue_number: int, body: str) -> bool:
        """Update a GitHub issue body."""
        try:
            # Escape special characters in body
            escaped_body = body.replace('"', '\\"').replace('\n', '\\n')
            
            result = subprocess.run(
                f'gh issue edit {issue_number} --body "{escaped_body}"',
                shell=True,
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                logger.info(f"Updated issue #{issue_number}")
                return True
            else:
                logger.error(f"Failed to update issue: {result.stderr}")
                return False
        except Exception as e:
            logger.error(f"Error updating issue: {e}")
            return False
    
    def add_label(self, issue_number: int, label: str) -> bool:
        """Add label to issue."""
        try:
            result = subprocess.run(
                f"gh issue edit {issue_number} --add-label {label}",
                shell=True,
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                logger.info(f"Added label '{label}' to issue #{issue_number}")
                return True
            else:
                logger.error(f"Failed to add label: {result.stderr}")
                return False
        except Exception as e:
            logger.error(f"Error adding label: {e}")
            return False
    
    def create_deployment_tracking_issue(self,
                                         deployment_id: str,
                                         components: List[str],
                                         category: str = "deployment") -> Optional[int]:
        """Create tracking issue for deployment."""
        title = f"[{category.upper()}] Deployment {deployment_id}"
        
        body = f"""## À la carte Deployment

**Deployment ID:** {deployment_id}
**Created:** {datetime.now().isoformat()}
**Status:** 🔄 In Progress

### Components
{self._format_component_list(components)}

### Progress
- [ ] Remove embedded secrets
- [ ] Migrate to GSM/Vault/KMS
- [ ] Setup dynamic credential retrieval
- [ ] Setup credential rotation
- [ ] Verify all systems operational

### Audit Trail
See `.deployment-audit/deployment_{deployment_id}.jsonl` for detailed logs.

### Next Steps
1. Monitor deployment progress
2. Review audit logs for errors
3. Close issue when deployment completes

---
*Automatically created by deployment orchestrator*
"""
        
        return self.create_issue(
            title=title,
            body=body,
            labels=["deployment", "automation"],
            assignees=["akushnir"]
        )
    
    def create_component_issue(self,
                               component_id: str,
                               component_name: str,
                               status: str,
                               deployment_id: str,
                               details: Dict[str, Any] = None) -> Optional[int]:
        """Create issue for individual component deployment."""
        status_emoji = {
            "completed": "✅",
            "in-progress": "🔄",
            "failed": "❌",
            "skipped": "⏭️",
        }.get(status, "❓")
        
        title = f"[{status_emoji}] Component: {component_name} ({component_id})"
        
        body = f"""## Component Deployment Status

**Component ID:** {component_id}
**Name:** {component_name}
**Status:** {status_emoji} {status.title()}
**Deployment ID:** {deployment_id}

### Details
{json.dumps(details or {}, indent=2)}

### Actions
- [ ] Verify component functioning
- [ ] Check logs for issues
- [ ] Update documentation if needed

---
*Tracked automatically by deployment orchestrator*
"""
        
        labels = ["component", "deployment", status]
        
        return self.create_issue(
            title=title,
            body=body,
            labels=labels,
            assignees=["akushnir"]
        )
    
    def _format_component_list(self, components: List[str]) -> str:
        """Format component list as markdown."""
        return '\n'.join(f"- [ ] {comp}" for comp in components)


class GitHubIssueTracker:
    """Track related issues through deployment lifecycle."""
    
    def __init__(self):
        self.automation = GitHubIssueAutomation()
        self.tracking_issues: Dict[str, int] = {}  # component_id -> issue_number
    
    def track_deployment(self, deployment_id: str, components: List[str]) -> Optional[int]:
        """Create master tracking issue for deployment."""
        issue_number = self.automation.create_deployment_tracking_issue(
            deployment_id=deployment_id,
            components=components
        )
        
        if issue_number:
            self.tracking_issues[f"deployment_{deployment_id}"] = issue_number
        
        return issue_number
    
    def track_component(self,
                        component_id: str,
                        component_name: str,
                        status: str,
                        deployment_id: str,
                        details: Dict[str, Any] = None) -> Optional[int]:
        """Create tracking issue for component."""
        issue_number = self.automation.create_component_issue(
            component_id=component_id,
            component_name=component_name,
            status=status,
            deployment_id=deployment_id,
            details=details
        )
        
        if issue_number:
            self.tracking_issues[component_id] = issue_number
        
        return issue_number
    
    def close_tracking_issue(self, component_id: str) -> bool:
        """Close tracking issue when deployment completes."""
        if component_id in self.tracking_issues:
            return self.automation.close_issue(self.tracking_issues[component_id])
        return False


if __name__ == "__main__":
    import sys
    
    tracker = GitHubIssueTracker()
    
    # Example: Create deployment tracking issue
    deployment_id = "deploy-test-001"
    components = ["remove-embedded-secrets", "migrate-to-gsm", "setup-credential-rotation"]
    
    print(f"\nCreating deployment tracking issue for {deployment_id}...")
    issue_number = tracker.track_deployment(deployment_id, components)
    
    if issue_number:
        print(f"✅ Created issue #{issue_number}")
    else:
        print("❌ Failed to create issue")
        sys.exit(1)
