#!/usr/bin/env python3
"""
Phase 5 Stage 2: Credential Action Integration
Adds get-ephemeral-credential@v1 action calls to all workflows
"""

import re
import yaml
from pathlib import Path
from datetime import datetime
from collections import defaultdict

class WorkflowCredentialIntegrator:
    def __init__(self, workflow_dir=".github/workflows"):
        self.workflow_dir = Path(workflow_dir)
        self.modified = []
        self.failed = []
        self.stats = defaultdict(int)

    def extract_secrets_from_text(self, text):
        """Extract all secret references as plain text patterns"""
        # Pattern: ${{ secrets.SECRET_NAME }}
        pattern = r'\$\{\{\s*secrets\.([A-Z_][A-Z0-9_]*)\s*\}\}'
        return sorted(set(re.findall(pattern, text)))

    def migrate_workflow_file(self, filepath):
        """Migrate single workflow file"""
        try:
            # Read raw content
            with open(filepath, 'r') as f:
                content = f.read()
            
            # Extract secrets
            secrets = self.extract_secrets_from_text(content)
            
            if not secrets:
                return 'no_secrets'
            
            # Skip if only GITHUB_TOKEN
            non_auto = [s for s in secrets if s != 'GITHUB_TOKEN']
            if not non_auto:
                return 'github_token_only'
            
            # Parse file for jobs structure
            try:
                workflow = yaml.safe_load(content)
            except:
                return 'yaml_invalid'
            
            if not workflow or 'jobs' not in workflow:
                return 'no_jobs'
            
            # Build credential action YAML strings (for later insertion)
            cred_steps = []
            replacements = []
            
            for secret in non_auto:
                step_id = f"'{secret.lower()}'"  # Use quotes for safety
                cred_step = f"""      - name: Get Credential [{secret}]
        id: cred_{secret.lower()}
        uses: kushin77/get-ephemeral-credential@v1
        with:
          credential-name: {secret}
          retrieve-from: 'auto'
          cache-ttl: 600
          audit-log: true"""
                
                cred_steps.append(cred_step)
                
                # Plan replacements
                old_ref = f"${{{{ secrets.{secret} }}}}"
                new_ref = f"${{{{ steps.cred_{secret.lower()}.outputs.credential }}}}"
                replacements.append((old_ref, new_ref))
            
            # Build modified content
            modified = content
            
            # Add credential steps before first "run:" command
            run_pattern = re.compile(r'^(\s+)run:', re.MULTILINE)
            match = run_pattern.search(modified)
            
            if match:
                # Insert all credential steps before first run
                indent = match.group(1)
                insertion_point = match.start()
                cred_block = '\n'.join(cred_steps) + '\n\n'
                modified = modified[:insertion_point] + cred_block + modified[insertion_point:]
            
            # Replace secret references
            for old_ref, new_ref in replacements:
                modified = modified.replace(old_ref, new_ref)
            
            # Validate YAML
            try:
                yaml.safe_load(modified)
            except:
                return 'yaml_invalid_after'
            
            # Write back
            with open(filepath, 'w') as f:
                f.write(modified)
            
            self.modified.append(filepath.name)
            self.stats['modified'] += 1
            return 'migrated'
        
        except Exception as e:
            self.failed.append((filepath.name, str(e)))
            self.stats['failed'] += 1
            return f'error: {str(e)[:30]}'

    def migrate_all(self):
        """Migrate all workflows"""
        workflows = sorted(self.workflow_dir.glob("*.yml"))
        
        print(f"\n{'='*60}")
        print("Phase 5 Stage 2: Credential Action Integration")
        print(f"{'='*60}\n")
        
        for wf in workflows:
            result = self.migrate_workflow_file(wf)
            
            status_map = {
                'migrated': '✅',
                'no_secrets': '⏭️',
                'github_token_only': '⏭️',
                'yaml_invalid': '⚠️',
                'no_jobs': '⏭️',
            }
            
            symbol = status_map.get(result, '❌')
            print(f"{symbol} {wf.name}: {result}")
            self.stats[result] += 1
        
        # Report
        print(f"\n{'='*60}")
        print("Summary")
        print(f"{'='*60}\n")
        print(f"Total processed: {len(workflows)}")
        print(f"Modified: {self.stats['modified']}")
        print(f"Failed: {self.stats['failed']}")
        print(f"Skipped: {len(workflows) - self.stats['modified'] - self.stats['failed']}")
        
        if self.failed:
            print(f"\nFailed workflows:")
            for name, error in self.failed:
                print(f"  - {name}: {error}")
        
        print(f"\n✅ Stage 2 Complete")
        print(f"Modified workflows: {self.stats['modified']}")
        print(f"Ready for commit and testing\n")
        
        return self.stats['modified'] > 0


if __name__ == '__main__':
    integrator = WorkflowCredentialIntegrator()
    integrator.migrate_all()
