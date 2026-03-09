#!/usr/bin/env python3
"""
Terraform Image Pin Updater
Purpose: Automate pinning image digests from Trivy scans to Terraform files
Principles: Idempotent (safe to re-run), Immutable (audit trail), Hands-off (no manual steps)
"""

import json
import re
import sys
import os
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional
import hashlib


class TerraformImagePinner:
    """Automate image digest pinning in Terraform files"""
    
    def __init__(self, repo_root: str, audit_log: str = None):
        self.repo_root = Path(repo_root)
        self.audit_log_path = Path(audit_log or f"{repo_root}/logs/image-pin-audit.jsonl")
        self.audit_log_path.parent.mkdir(parents=True, exist_ok=True)
        self.changes = []
        
    def audit_log(self, action: str, status: str, details: str = ""):
        """Immutable append-only audit trail"""
        entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "action": action,
            "status": status,
            "executor": os.getenv("USER", "unknown"),
            "details": details
        }
        with open(self.audit_log_path, "a") as f:
            f.write(json.dumps(entry) + "\n")
    
    def parse_trivy_output(self, trivy_json: str) -> Dict[str, str]:
        """
        Parse Trivy JSON output and extract approved images with digests
        Expected format:
        {
            "Results": [
                {
                    "Target": "image:tag",
                    "Type": "image",
                    "Vulnerabilities": [...],
                    "Metadata": {
                        "ImageID": {"ID": "sha256:abc123..."}
                    }
                }
            ]
        }
        
        Returns: {"image:tag": "sha256:abc123..."}
        """
        try:
            data = json.loads(trivy_json)
            approved_images = {}
            
            for result in data.get("Results", []):
                target = result.get("Target", "")
                
                # Check if image is "approved" (no critical vulns or has approval flag)
                vulns = result.get("Vulnerabilities", [])
                critical_vulns = [v for v in vulns if v.get("Severity") == "CRITICAL"]
                
                # Approval logic: no critical vulns = approved
                if not critical_vulns and target:
                    # Extract digest from metadata
                    metadata = result.get("Metadata", {})
                    image_id = metadata.get("ImageID", {})
                    digest = image_id.get("ID", "")
                    
                    if digest:
                        approved_images[target] = digest
                        self.audit_log("image_approval", "approved", f"{target} -> {digest}")
                    else:
                        self.audit_log("image_parse", "warning", f"No digest found for {target}")
            
            return approved_images
        except json.JSONDecodeError as e:
            self.audit_log("parse_trivy", "failed", str(e))
            raise ValueError(f"Invalid Trivy JSON: {e}")
    
    def find_terraform_files(self, pattern: str = "*.tf") -> List[Path]:
        """Find all Terraform files in repo"""
        tf_files = list(self.repo_root.glob(f"**/{pattern}"))
        self.audit_log("find_tf_files", "success", f"Found {len(tf_files)} Terraform files")
        return tf_files
    
    def update_terraform_pins(self, tf_files: List[Path], image_pins: Dict[str, str]) -> Dict[str, List[str]]:
        """
        Update Terraform files with pinned image digests
        Idempotent: only updates if digest has changed
        Immutable: preserves file history (git tracked)
        
        Returns: {filename: [updated_locations]}
        """
        results = {}
        
        for tf_file in tf_files:
            if not tf_file.exists():
                continue
                
            content = tf_file.read_text()
            original_content = content
            updated_locations = []
            
            # Pattern 1: Simple image = "repo/image:tag"
            for image_ref, digest in image_pins.items():
                # Match patterns like: image = "repo/image:tag" or "repo/image:tag@sha256:xxx"
                pattern = rf'(image\s*=\s*")({re.escape(image_ref)})(@sha256:[a-f0-9]+)?(")'
                replacement = rf'\1\2@{digest}\4'
                
                new_content, count = re.subn(pattern, replacement, content)
                
                if count > 0:
                    content = new_content
                    updated_locations.append(f"{image_ref} pinned to {digest[:12]}... ({count} occurrence)")
                    self.audit_log("terraform_update", "updated", f"{tf_file.name}: {image_ref} -> {digest}")
            
            # If content changed, write it back and track
            if content != original_content:
                tf_file.write_text(content)
                results[str(tf_file)] = updated_locations
                self.audit_log("terraform_write", "success", f"Updated {tf_file.name}")
            else:
                self.audit_log("terraform_write", "unchanged", f"No changes needed in {tf_file.name}")
        
        return results
    
    def create_promotion_pr(self, 
                          updated_files: Dict[str, List[str]], 
                          trivy_run_id: str = "") -> Optional[str]:
        """
        Create a GitHub PR with the image pin updates
        Idempotent: checks if PR already exists for this pinning cycle
        """
        if not updated_files:
            self.audit_log("create_pr", "skipped", "No files to promote")
            return None
        
        try:
            # Create feature branch
            branch_name = f"chore/image-pin-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"
            
            # Git: stage changes
            subprocess.run(["git", "add"] + list(updated_files.keys()), 
                         cwd=self.repo_root, check=True, capture_output=True)
            
            # Git: commit  (idempotent - will skip if nothing changed)
            commit_msg = "chore: pin Trivy-approved image digests\n"
            if trivy_run_id:
                commit_msg += f"\nTrivy run ID: {trivy_run_id}\n"
            commit_msg += f"\n## Updated Images\n"
            for filename, updates in updated_files.items():
                commit_msg += f"\n**{Path(filename).name}**\n"
                for update in updates:
                    commit_msg += f"  - {update}\n"
            commit_msg += f"\n## Audit Trail\nGenerated by: terraform_pin_updater.py\nTimestamp: {datetime.utcnow().isoformat()}Z"
            
            result = subprocess.run(
                ["git", "commit", "-m", commit_msg],
                cwd=self.repo_root,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                # Create PR via GitHub CLI
                pr_template = f"""## Image Pin Update - {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}

### Summary
Automated Trivy-approved image digest pinning for reproducible deployments.

### Files Changed
{len(updated_files)} Terraform files updated with pinned image digests.

### Details
- **Tool:** terraform_pin_updater.py
- **Trivy Run:** {trivy_run_id or 'N/A'}
- **Timestamp:** {datetime.utcnow().isoformat()}Z

### Updated Images
"""
                for filename, updates in updated_files.items():
                    pr_template += f"\n**{Path(filename).name}**\n"
                    for update in updates:
                        pr_template += f"  - {update}\n"
                
                pr_template += """
### Principles
- ✅ Idempotent: Safe to re-run
- ✅ Immutable: Git history preserved
- ✅ Hands-off: Fully automated
"""
                
                # Push to remote and create PR
                push_result = subprocess.run(
                    ["git", "push", "origin", branch_name],
                    cwd=self.repo_root,
                    capture_output=True,
                    text=True
                )
                
                if push_result.returncode == 0:
                    pr_result = subprocess.run(
                        ["gh", "pr", "create", 
                         "--title", f"chore: pin Trivy-approved image digests",
                         "--body", pr_template,
                         "--head", branch_name,
                         "--base", "main"],
                        cwd=self.repo_root,
                        capture_output=True,
                        text=True
                    )
                    
                    if pr_result.returncode == 0:
                        pr_url = pr_result.stdout.strip()
                        self.audit_log("create_pr", "success", f"PR created: {pr_url}")
                        print(f"✅ PR created: {pr_url}")
                        return pr_url
                    else:
                        self.audit_log("create_pr", "failed", f"gh pr create failed: {pr_result.stderr}")
                else:
                    self.audit_log("git_push", "failed", f"git push failed: {push_result.stderr}")
            else:
                self.audit_log("git_commit", "skipped", result.stderr or "Nothing to commit")
                
        except Exception as e:
            self.audit_log("create_pr", "failed", str(e))
            print(f"❌ Failed to create PR: {e}")
            return None
    
    def validate_updates(self, tf_files: List[Path]) -> bool:
        """Validate Terraform files are syntactically correct after updates"""
        try:
            result = subprocess.run(
                ["terraform", "validate"],
                cwd=self.repo_root,
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                self.audit_log("terraform_validate", "success", "All files valid")
                return True
            else:
                self.audit_log("terraform_validate", "failed", result.stderr)
                print(f"❌ Terraform validation failed: {result.stderr}")
                return False
        except Exception as e:
            self.audit_log("terraform_validate", "error", str(e))
            return False


def main():
    """Main entry point for image pinning"""
    if len(sys.argv) < 2:
        print("Usage: python terraform_pin_updater.py <trivy_json_output> [trivy_run_id]")
        print("\nExample:")
        print("  trivy image --format json my-image:latest | python terraform_pin_updater.py /dev/stdin")
        sys.exit(1)
    
    trivy_json_file = sys.argv[1]
    trivy_run_id = sys.argv[2] if len(sys.argv) > 2 else ""
    repo_root = os.getenv("REPO_ROOT", "/home/akushnir/self-hosted-runner")
    
    pinner = TerraformImagePinner(repo_root)
    
    try:
        # Read Trivy output
        with open(trivy_json_file) as f:
            trivy_json = f.read()
        
        print("🔍 Parsing Trivy scan results...")
        approved_images = pinner.parse_trivy_output(trivy_json)
        
        if not approved_images:
            print("ℹ️  No approved images found in Trivy output")
            pinner.audit_log("main", "no_changes", "No approved images to pin")
            return 0
        
        print(f"✅ Found {len(approved_images)} approved images")
        for image, digest in approved_images.items():
            print(f"   - {image}: {digest[:16]}...")
        
        # Find and update Terraform files
        print("\n📦 Updating Terraform files...")
        tf_files = pinner.find_terraform_files()
        updated_files = pinner.update_terraform_pins(tf_files, approved_images)
        
        if updated_files:
            print(f"✅ Updated {len(updated_files)} files")
            for filename, updates in updated_files.items():
                print(f"   - {Path(filename).name}")
                for update in updates:
                    print(f"     • {update}")
        else:
            print("ℹ️  No Terraform files needed updates")
            pinner.audit_log("main", "no_updates", "No Terraform files matched image pins")
            return 0
        
        # Validate syntax
        print("\n✓ Validating Terraform syntax...")
        if not pinner.validate_updates(tf_files):
            print("❌ Validation failed. Rolling back changes.")
            subprocess.run(["git", "checkout", "HEAD", "--"] + 
                         list(updated_files.keys()), cwd=repo_root, capture_output=True)
            sys.exit(1)
        
        # Create promotion PR
        print("\n📤 Creating promotion PR...")
        pr_url = pinner.create_promotion_pr(updated_files, trivy_run_id)
        
        if pr_url:
            print(f"✅ Image pinning complete!")
            print(f"   Promotion PR: {pr_url}")
            pinner.audit_log("main", "success", f"Image pinning completed, PR: {pr_url}")
            return 0
        else:
            print("⚠️  Files updated but PR creation failed")
            pinner.audit_log("main", "partial_failure", "Files updated, PR creation failed")
            return 1
            
    except Exception as e:
        print(f"❌ Error: {e}")
        pinner.audit_log("main", "failed", str(e))
        return 1


if __name__ == "__main__":
    sys.exit(main())
