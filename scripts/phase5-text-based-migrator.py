#!/usr/bin/env python3
"""
Phase 5 Text-Based Batch Migrator
Uses regex-based replacements instead of YAML parsing for robustness
"""

import os
import re
import sys
from pathlib import Path
from collections import defaultdict

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

class TextBasedMigrator:
    def __init__(self, workflow_dir=".github/workflows", batch='batch2'):
        self.workflow_dir = Path(workflow_dir)
        self.batch = batch
        self.target_workflows = set(BATCHES.get(batch, []))
        self.modified = []
        self.failed = []
        self.stats = defaultdict(int)

    def extract_secrets(self, text):
        """Extract unique secret names from workflow"""
        # Match: secrets.NAME (but not GITHUB_TOKEN)
        pattern = r'secrets\.([A-Za-z_][A-Za-z0-9_]*)'
        matches = re.findall(pattern, text)
        secrets = sorted(set(m for m in matches if m != 'GITHUB_TOKEN'))
        return secrets

    def migrate_workflow_file(self, filepath):
        """Migrate workflow using text-based approach"""
        try:
            with open(filepath, 'r') as f:
                content = f.read()
            
            # Extract secrets
            secrets = self.extract_secrets(content)
            if not secrets:
                return 'no_secrets'
            
            # Build credential steps
            cred_steps_text = self._build_credential_steps_text(secrets)
            
            # Find insertion point: after "actions/checkout" line
            checkout_pattern = r'(\s+- uses: actions/checkout@[\w.]+.*?)(\n\s+-)'
            match = re.search(checkout_pattern, content, re.DOTALL)
            
            if not match:
                # Try simpler pattern
                checkout_pattern = r'(actions/checkout@[\w.]+)'
                if checkout_pattern not in content:
                    return 'no_checkout_step'
                
                # Find the end of the checkout step block
                lines = content.split('\n')
                checkout_line_idx = -1
                for i, line in enumerate(lines):
                    if 'actions/checkout' in line:
                        checkout_line_idx = i
                        break
                
                if checkout_line_idx < 0:
                    return 'no_checkout_found'
                
                # Find the next step (next line starting with -) after checkout block
                next_step_idx = checkout_line_idx + 1
                for i in range(checkout_line_idx + 1, len(lines)):
                    if lines[i].strip() and not lines[i].startswith(' ' * 6):
                        if lines[i].strip().startswith('-') or 'name:' in lines[i]:
                            next_step_idx = i
                            break
                
                # Insert credential steps
                lines.insert(next_step_idx, '')
                lines.insert(next_step_idx, cred_steps_text)
                modified = '\n'.join(lines)
            else:
                # Use regex match result
                modified = content[:match.end(1)] + '\n' + cred_steps_text + content[match.start(2):]
            
            # Replace secret references
            for secret in secrets:
                old_ref = f"${{{{ secrets.{secret} }}}}"
                new_ref = f"${{{{ steps.cred_{secret.lower()}.outputs.credential }}}}"
                modified = modified.replace(old_ref, new_ref)
            
            # Light YAML validation
            if modified.count('{') != content.count('{') + cred_steps_text.count('{'):
                return 'brace_mismatch'
            
            # Write back
            with open(filepath, 'w') as f:
                f.write(modified)
            
            self.modified.append(filepath.name)
            self.stats['modified'] += 1
            return 'migrated'
        
        except Exception as e:
            self.failed.append((filepath.name, str(e)[:50]))
            self.stats['failed'] += 1
            return f'error: {str(e)[:30]}'

    def _build_credential_steps_text(self, secrets):
        """Build credential steps as text"""
        lines = []
        for secret in secrets:
            lines.append(f"      - name: Get Credential [{secret}]")
            lines.append(f"        id: cred_{secret.lower()}")
            lines.append(f"        uses: kushin77/get-ephemeral-credential@v1")
            lines.append(f"        with:")
            lines.append(f"          credential-name: {secret}")
            lines.append(f"          retrieve-from: 'auto'")
            lines.append(f"          cache-ttl: 600")
            lines.append(f"          audit-log: true")
            lines.append("")
        return '\n'.join(lines)

    def migrate_batch(self):
        """Migrate all workflows in batch"""
        print(f"\n{'='*70}")
        print(f"Phase 5 Text-Based Migration: {self.batch.upper()}")
        print(f"{'='*70}\n")
        
        workflows = sorted(self.workflow_dir.glob("*.yml"))
        target_wfs = [w for w in workflows if w.name in self.target_workflows]
        
        print(f"Processing {len(target_wfs)} workflows:\n")
        
        for wf in target_wfs:
            result = self.migrate_workflow_file(wf)
            icon = '✅' if result == 'migrated' else ('⏭️' if 'no_' in result else '❌')
            print(f"{icon} {wf.name}: {result}")
            self.stats[result] += 1
        
        print(f"\n{'='*70}")
        print(f"Summary ({self.batch.upper()})")
        print(f"{'='*70}\n")
        print(f"Target: {len(self.target_workflows)}")
        print(f"Found: {len(target_wfs)}")
        print(f"Modified: {self.stats['modified']}")
        print(f"Failed: {self.stats['failed']}")
        
        if self.failed:
            print(f"\nFailed:")
            for name, err in self.failed:
                print(f"  ❌ {name}: {err}")
        
        print(f"\n✅ {self.batch.upper()} Complete\n")
        return self.stats['modified'] > 0


if __name__ == '__main__':
    batch = sys.argv[1] if len(sys.argv) > 1 else 'batch2'
    
    if batch not in BATCHES:
        print(f"❌ Unknown batch: {batch}")
        print(f"Available: {', '.join(sorted(BATCHES.keys()))}")
        sys.exit(1)
    
    migrator = TextBasedMigrator(batch=batch)
    migrator.migrate_batch()
    sys.exit(0)
