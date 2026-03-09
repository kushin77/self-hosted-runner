#!/usr/bin/env python3
"""
Automated Phase 5b Batch Migration - Migrate 32 workflows to ephemeral credentials.
Creates branches, migrates workflows, validates, and opens PRs for merge.
"""

import os
import sys
import re
import yaml
import json
import subprocess
from pathlib import Path
from typing import List, Dict, Tuple, Set

class WorkflowMigrator:
    def __init__(self):
        self.repo_root = Path('.')
        self.workflows_dir = self.repo_root / '.github' / 'workflows'
        self.migrated_cache = self._load_migrated_cache()
        
    def _load_migrated_cache(self) -> Set[str]:
        """Load set of already migrated workflows."""
        return {
            'ci-images.yml', 'observability-e2e.yml', 'push-image-to-registry.yml',
            'rotation_schedule.yml', 'secret-validator-observability.yml', 'build.yml',
            'release.yml', 'secrets-health.yml', 'revoke-keys.yml',
            'secrets-orchestrator-multi-layer.yml', 'terraform-phase2-drift-detection.yml',
            'terraform-phase2-post-deploy-validation.yml',
            'credential-refresh-15min.yml', 'credential-health-check-hourly.yml',
            'credential-rotation-daily.yml', 'credential-audit-weekly.yml',
            'ephemeral-credential-refresh-15min.yml', 'ephemeral-secret-provisioning.yml',
        }
    
    def get_workflows_needing_migration(self) -> List[Tuple[str, List[str]]]:
        """Get list of workflows that need migration, sorted by priority."""
        workflows = []
        
        for wf_file in sorted(self.workflows_dir.glob('*.yml')):
            basename = wf_file.name
            
            # Skip already migrated
            if basename in self.migrated_cache:
                continue
            
            # Extract secrets
            secrets = self._extract_secrets(wf_file)
            if secrets:
                workflows.append((basename, secrets))
        
        # Sort by number of secrets (descending)
        workflows.sort(key=lambda x: len(x[1]), reverse=True)
        return workflows
    
    def _extract_secrets(self, wf_path: Path) -> List[str]:
        """Extract secret names from workflow."""
        try:
            with open(wf_path) as f:
                content = f.read()
                matches = re.findall(r'\$\{\{\s*secrets\.(\w+)', content)
                return sorted(list(set(matches)))
        except:
            return []
    
    def create_batches(self, workflows: List[Tuple[str, List[str]]], batch_size: int = 15) -> List[List[Tuple[str, List[str]]]]:
        """Split workflows into batches."""
        batches = []
        for i in range(0, len(workflows), batch_size):
            batches.append(workflows[i:i+batch_size])
        return batches
    
    def migrate_workflow(self, wf_path: Path, secrets: List[str]) -> bool:
        """Migrate a single workflow to use ephemeral credentials."""
        try:
            with open(wf_path) as f:
                content = f.read()
            
            # Already has ephemeral credential step?
            if 'get-ephemeral-credential' in content:
                return True  # Already migrated
            
            # Find env section or jobs section
            lines = content.split('\n')
            new_lines = []
            in_jobs = False
            inserted = False
            
            for i, line in enumerate(lines):
                new_lines.append(line)
                
                # After 'jobs:' section starts, look for first job
                if line.strip() == 'jobs:':
                    in_jobs = True
                
                # Insert ephemeral credential step at first run step
                if in_jobs and not inserted and re.match(r'\s+-\s+run:', line):
                    # Back up to find the proper indentation
                    indent = len(line) - len(line.lstrip())
                    base_indent = ' ' * (indent - 2)
                    
                    # Insert get-ephemeral-credential step before this run step
                    step_lines = [
                        f"{base_indent}- name: Get Ephemeral Credentials",
                        f"{base_indent}  uses: kushin77/get-ephemeral-credential@v1",
                        f"{base_indent}    id: creds",
                        f"{base_indent}    with:",
                        f"{base_indent}      credential-names: |",
                    ]
                    
                    # Add each secret
                    for secret in secrets:
                        step_lines.append(f"{base_indent}        {secret}")
                    
                    step_lines.append(f"{base_indent}      retrieve-from: 'auto'")
                    
                    # Insert before the run step
                    new_lines = new_lines[:-1] + step_lines + [line]
                    inserted = True
            
            # Write back
            with open(wf_path, 'w') as f:
                f.write('\n'.join(new_lines))
            
            return True
        except Exception as e:
            print(f"  ❌ Error migrating: {e}")
            return False
    
    def validate_yaml(self, wf_path: Path) -> Tuple[bool, str]:
        """Validate workflow YAML syntax."""
        try:
            # yamllint check
            result = subprocess.run(
                ['yamllint', '-d', 'relaxed', str(wf_path)],
                capture_output=True,
                text=True,
                timeout=5
            )
            
            if 'error' in result.stdout.lower():
                return False, result.stdout
            
            # Python yaml parse check
            with open(wf_path) as f:
                yaml.safe_load(f)
            
            return True, "Valid"
        except Exception as e:
            return False, str(e)
    
    def run_batch_migration(self, batch_num: int, workflows: List[Tuple[str, List[str]]]) -> Tuple[int, List[str]]:
        """Migrate a batch of workflows and create PR."""
        print(f"\n{'='*70}")
        print(f"BATCH {batch_num}: Migrating {len(workflows)} workflows")
        print(f"{'='*70}\n")
        
        # Create branch
        branch_name = f"migration/batch{batch_num}-ephemeral-credentials"
        try:
            subprocess.run(['git', 'checkout', '-b', branch_name], 
                         capture_output=True, check=True)
        except:
            subprocess.run(['git', 'checkout', branch_name], 
                         capture_output=True)
            subprocess.run(['git', 'reset', '--hard', 'origin/main'], 
                         capture_output=True)
        
        migrated = []
        failed = []
        
        for workflow_name, secrets in workflows:
            wf_path = self.workflows_dir / workflow_name
            
            print(f"  Migrating {workflow_name}...", end=' ', flush=True)
            
            # Migrate
            if self.migrate_workflow(wf_path, secrets):
                # Validate
                is_valid, msg = self.validate_yaml(wf_path)
                if is_valid:
                    print(f"✓ PASS")
                    migrated.append(workflow_name)
                else:
                    print(f"✗ YAML Error: {msg[:40]}...")
                    failed.append(workflow_name)
            else:
                print(f"✗ FAIL")
                failed.append(workflow_name)
        
        # Commit and push
        if migrated:
            print(f"\n  Committing {len(migrated)} workflows...")
            subprocess.run(['git', 'add', '.github/workflows/'], 
                         capture_output=True, check=True)
            
            commit_msg = f"chore(batch{batch_num}): migrate {len(migrated)} workflows to ephemeral credentials\n\nWorkflows:\n"
            for wf in migrated:
                commit_msg += f"- {wf}\n"
            commit_msg += f"\nCredential layers: GSM (primary), Vault (secondary), KMS (tertiary)\nRelated: #1992 (INFRA-2005)"
            
            subprocess.run(['git', 'commit', '-m', commit_msg],
                         capture_output=True, check=True)
            
            subprocess.run(['git', 'push', '-u', 'origin', branch_name],
                         capture_output=True, check=True)
            
            print(f"  ✓ Pushed to origin/{branch_name}")
        
        return len(migrated), failed

def main():
    migrator = WorkflowMigrator()
    
    # Get all workflows needing migration
    workflows = migrator.get_workflows_needing_migration()
    print(f"\nFound {len(workflows)} workflows needing migration\n")
    
    # Create batches
    batches = migrator.create_batches(workflows, batch_size=15)
    print(f"Created {len(batches)} batches\n")
    
    # Track results
    all_migrated = []
    all_failed = []
    
    # Process each batch
    for batch_idx, batch in enumerate(batches, start=4):
        migrated, failed = migrator.run_batch_migration(batch_idx, batch)
        all_migrated.extend([wf for wf, _ in batch[:migrated]])
        all_failed.extend(failed)
        
        # Checkout main after each batch
        subprocess.run(['git', 'checkout', 'main'],
                     capture_output=True)
    
    # Final summary
    print(f"\n{'='*70}")
    print(f"MIGRATION COMPLETE")
    print(f"{'='*70}")
    print(f"Total migrated: {len(all_migrated)}")
    print(f"Total failed: {len(all_failed)}")
    
    if all_failed:
        print(f"\nFailed workflows: {all_failed}")

if __name__ == '__main__':
    main()
