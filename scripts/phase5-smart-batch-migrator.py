#!/usr/bin/env python3
"""
Phase 5 Stage 2 Smart Batch Migrator
Properly migrates workflows to ephemeral credentials with correct YAML structure
"""

import os
import re
import yaml
from pathlib import Path
from collections import defaultdict
import sys

BATCHES = {
    'batch2': [
        'ephemeral-secret-provisioning.yml',
        'secret-rotation-mgmt-token.yml',
        'revoke-runner-mgmt-token.yml',
        'revoke-deploy-ssh-key.yml',
        'revoke-keys.yml',
        'phase3-automated-deploy.yml',
        'phase3-bootstrap-wip.yml',
        'deploy.yml',
    ],
    'batch3': [
        'gcp-gsm-breach-recovery.yml',
        'gcp-gsm-rotation.yml',
        'gcp-gsm-sync-secrets.yml',
        'hands-off-health-deploy.yml',
        'store-leaked-to-gsm-and-remove.yml',
        'store-slack-to-gsm.yml',
        'terraform-phase2-drift-detection.yml',
        'terraform-phase2-final-plan-apply.yml',
        'terraform-phase2-post-deploy-validation.yml',
        'secrets-orchestrator-multi-layer.yml',
    ],
    'batch4': [
        'build.yml',
        'release.yml',
        'operational-health-dashboard.yml',
        'secrets-health-dashboard.yml',
        'secrets-health.yml',
    ],
}

class SmartWorkflowMigrator:
    def __init__(self, workflow_dir=".github/workflows", batch='batch2'):
        self.workflow_dir = Path(workflow_dir)
        self.batch = batch
        self.target_workflows = set(BATCHES.get(batch, []))
        self.modified = []
        self.failed = []
        self.skipped = []
        self.stats = defaultdict(int)

    def extract_secrets(self, text):
        """Extract secret references from workflow text"""
        pattern = r'secrets\.([A-Za-z_][A-Za-z0-9_]*)'
        matches = re.findall(pattern, text)
        return sorted(set(m for m in matches if m != 'GITHUB_TOKEN'))

    def build_credential_step(self, secret_name):
        """Build a single credential retrieval step"""
        step_id = f"cred_{secret_name.lower()}"
        return {
            'name': f'Get Credential [{secret_name}]',
            'id': step_id,
            'uses': 'kushin77/get-ephemeral-credential@v1',
            'with': {
                'credential-name': secret_name,
                'retrieve-from': 'auto',
                'cache-ttl': 600,
                'audit-log': True,
            }
        }

    def find_checkout_step(self, job_steps):
        """Find the index of the checkout step"""
        for idx, step in enumerate(job_steps):
            if isinstance(step, dict):
                uses = step.get('uses', '')
                if 'checkout' in uses:
                    return idx
        return -1

    def migrate_workflow_file(self, filepath):
        """Migrate single workflow file using proper YAML structure"""
        try:
            # Read file
            with open(filepath, 'r') as f:
                content = f.read()
            
            # Extract all secrets
            secrets = self.extract_secrets(content)
            if not secrets:
                return 'no_secrets'
            
            # Parse YAML
            try:
                workflow = yaml.safe_load(content)
            except Exception as e:
                return f'yaml_parse_error: {str(e)[:30]}'
            
            if not workflow or not isinstance(workflow, dict):
                return 'empty_workflow'
            
            jobs = workflow.get('jobs', {})
            if not jobs:
                return 'no_jobs'
            
            # Track if any job was modified
            any_modified = False
            
            # Process each job
            for job_name, job_data in jobs.items():
                if not isinstance(job_data, dict):
                    continue
                
                steps = job_data.get('steps', [])
                if not isinstance(steps, list) or not steps:
                    continue
                
                # Find checkout step
                checkout_idx = self.find_checkout_step(steps)
                if checkout_idx < 0:
                    continue
                
                # Collect existing credential step IDs to avoid duplicates
                existing_cred_ids = set()
                for step in steps:
                    if isinstance(step, dict):
                        step_id = step.get('id', '')
                        if step_id.startswith('cred_'):
                            existing_cred_ids.add(step_id)
                
                # Build credential steps for this job
                new_steps = []
                for secret in secrets:
                    step_id = f"cred_{secret.lower()}"
                    if step_id not in existing_cred_ids:
                        new_steps.append(self.build_credential_step(secret))
                
                # Insert after checkout if we have new steps
                if new_steps:
                    job_data['steps'] = steps[:checkout_idx+1] + new_steps + steps[checkout_idx+1:]
                    any_modified = True
            
            if not any_modified:
                return 'no_steps_added'
            
            # Replace secret references in the modified workflow
            for secret in secrets:
                old_ref = f"${{{{ secrets.{secret} }}}}"
                new_ref = f"${{{{ steps.cred_{secret.lower()}.outputs.credential }}}}"
                workflow_str = yaml.dump(workflow, default_flow_style=False, sort_keys=False)
                workflow_str = workflow_str.replace(old_ref, new_ref)
                workflow = yaml.safe_load(workflow_str)
            
            # Validate final YAML
            try:
                final_str = yaml.dump(workflow, default_flow_style=False, sort_keys=False)
                yaml.safe_load(final_str)
            except Exception as e:
                return f'yaml_write_error: {str(e)[:30]}'
            
            # Write back (use simpler re-replacement approach to preserve formatting)
            with open(filepath, 'r') as f:
                modified_content = f.read()
            
            # Replace secret references in the text
            for secret in secrets:
                old_ref = f"${{{{ secrets.{secret} }}}}"
                new_ref = f"${{{{ steps.cred_{secret.lower()}.outputs.credential }}}}"
                modified_content = modified_content.replace(old_ref, new_ref)
            
            # Now insert credential steps after checkout in the text
            # Find the checkout step end and insert before the next step
            modified_content = self._insert_credential_steps_text(
                modified_content, 
                secrets,
                existing_cred_ids
            )
            
            # Final validation
            try:
                yaml.safe_load(modified_content)
            except Exception as e:
                return f'final_validation_error: {str(e)[:30]}'
            
            # Write back
            with open(filepath, 'w') as f:
                f.write(modified_content)
            
            self.modified.append(filepath.name)
            self.stats['modified'] += 1
            return 'migrated'
        
        except Exception as e:
            self.failed.append((filepath.name, str(e)))
            self.stats['failed'] += 1
            return f'error: {str(e)[:30]}'

    def _insert_credential_steps_text(self, content, secrets, existing_ids):
        """Insert credential steps as text at the right location"""
        # Pattern to find the end of a checkout step
        lines = content.split('\n')
        result = []
        i = 0
        inserted = False
        
        while i < len(lines):
            line = lines[i]
            result.append(line)
            
            # Look for checkout step and insert after it
            if not inserted and 'checkout@' in line:
                # Skip to end of this step
                j = i + 1
                while j < len(lines):
                    if lines[j].strip() and not lines[j].startswith(' ' * 8):
                        # Found next step
                        break
                    result.append(lines[j])
                    j += 1
                
                # Now insert credential steps before the next step
                if j < len(lines):
                    # Get indentation from the next step
                    next_step = lines[j]
                    indent = len(next_step) - len(next_step.lstrip())
                    
                    for secret in secrets:
                        step_id = f"cred_{secret.lower()}"
                        if step_id not in existing_ids:
                            # Add credential step
                            result.append(f"{' ' * (indent - 2)}- name: Get Credential [{secret}]")
                            result.append(f"{' ' * indent}id: {step_id}")
                            result.append(f"{' ' * indent}uses: kushin77/get-ephemeral-credential@v1")
                            result.append(f"{' ' * indent}with:")
                            result.append(f"{' ' * (indent + 2)}credential-name: {secret}")
                            result.append(f"{' ' * (indent + 2)}retrieve-from: 'auto'")
                            result.append(f"{' ' * (indent + 2)}cache-ttl: 600")
                            result.append(f"{' ' * (indent + 2)}audit-log: true")
                    
                    inserted = True
                    i = j - 1
            
            i += 1
        
        return '\n'.join(result)

    def migrate_batch(self):
        """Migrate all workflows in batch"""
        print(f"\n{'='*70}")
        print(f"Phase 5 Smart Migration: {self.batch.upper()}")
        print(f"{'='*70}\n")
        
        workflows = sorted(self.workflow_dir.glob("*.yml"))
        target_wfs = [w for w in workflows if w.name in self.target_workflows]
        
        print(f"Processing {len(target_wfs)} target workflows:\n")
        
        for wf in target_wfs:
            result = self.migrate_workflow_file(wf)
            
            status_icons = {
                'migrated': '✅',
                'no_secrets': '⏭️',
                'no_steps_added': '⏭️',
                'yaml_parse_error': '⚠️',
                'yaml_write_error': '⚠️',
                'error': '❌',
            }
            
            icon = status_icons.get(result if isinstance(result, str) and result in status_icons else 'error', '❌' if result.startswith('error') else '⚠️')
            print(f"{icon} {wf.name}: {result}")
            self.stats[result] += 1
        
        # Report
        print(f"\n{'='*70}")
        print(f"Summary ({self.batch.upper()})")
        print(f"{'='*70}\n")
        print(f"Target workflows: {len(self.target_workflows)}")
        print(f"Found: {len(target_wfs)}")
        print(f"Modified: {self.stats['modified']}")
        print(f"Failed: {self.stats['failed']}")
        
        if self.failed:
            print(f"\nFailed workflows:")
            for name, error in self.failed:
                print(f"  ❌ {name}: {error}")
        
        print(f"\n✅ {self.batch.upper()} Migration Complete")
        return self.stats['modified'] > 0


if __name__ == '__main__':
    batch = sys.argv[1] if len(sys.argv) > 1 else 'batch2'
    
    if batch not in BATCHES:
        print(f"Unknown batch: {batch}")
        print(f"Available: {', '.join(sorted(BATCHES.keys()))}")
        sys.exit(1)
    
    migrator = SmartWorkflowMigrator(batch=batch)
    success = migrator.migrate_batch()
    sys.exit(0 if success else 1)
