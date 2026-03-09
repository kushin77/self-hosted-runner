#!/usr/bin/env python3
"""
Phase 5 Batch Workflow Migration - Safe YAML Modification
Safely parses, modifies, and validates GitHub workflow YAML files
"""

import os
import sys
import yaml
import json
import re
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Set, Tuple

class WorkflowMigrator:
    def __init__(self, workflow_dir: str = ".github/workflows", backup_dir: str = None):
        self.workflow_dir = workflow_dir
        self.backup_dir = backup_dir or f"workflow-migration-backup-{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        self.modified_workflows: List[str] = []
        self.failed_workflows: List[Tuple[str, str]] = []
        self.skipped_workflows: List[str] = []
        
        Path(self.backup_dir).mkdir(exist_ok=True)

    def get_secrets_in_file(self, content: str) -> Set[str]:
        """Extract all secret references from workflow content"""
        pattern = r'\$\{\{\s*secrets\.([A-Z_][A-Z0-9_]*)\s*\}\}'
        return set(re.findall(pattern, content))

    def migrate_workflow(self, filepath: str) -> Tuple[bool, str]:
        """
        Migrate single workflow file to ephemeral credentials
        Returns: (success, message)
        """
        try:
            # Read file
            with open(filepath, 'r') as f:
                content = f.read()
            
            # Backup original
            backup_path = Path(self.backup_dir) / Path(filepath).name
            with open(backup_path, 'w') as f:
                f.write(content)
            
            # Parse YAML
            try:
                workflow = yaml.safe_load(content)
            except yaml.YAMLError as e:
                return False, f"Invalid YAML: {e}"
            
            if not workflow:
                return False, "Empty workflow"
            
            # Find secrets
            secrets = self.get_secrets_in_file(content)
            if not secrets:
                return True, "No secrets (skipped)"
            
            # Don't migrate GITHUB_TOKEN (it's automatic)
            secrets.discard('GITHUB_TOKEN')
            if not secrets:
                return True, "Only GITHUB_TOKEN (auto-managed)"
            
            # Add permissions
            if 'permissions' not in workflow:
                workflow['permissions'] = {}
            if not isinstance(workflow['permissions'], dict):
                workflow['permissions'] = {'contents': 'read'}
            
            workflow['permissions']['id-token'] = 'write'
            
            # Find jobs section
            if 'jobs' not in workflow:
                return False, "No jobs section"
            
            for job_name, job_spec in workflow['jobs'].items():
                if not isinstance(job_spec, dict):
                    continue
                
                if 'steps' not in job_spec:
                    job_spec['steps'] = []
                elif not isinstance(job_spec['steps'], list):
                    continue
                
                # Add credential steps at beginning
                new_steps = []
                for secret_name in sorted(secrets):
                    step_id = f"cred_{secret_name.lower()}"
                    new_steps.append({
                        'name': f'Get Credential [{secret_name}]',
                        'id': step_id,
                        'uses': 'kushin77/get-ephemeral-credential@v1',
                        'with': {
                            'credential-name': secret_name,
                            'retrieve-from': 'auto',
                            'cache-ttl': 600,
                            'audit-log': True
                        }
                    })
                
                # Insert credential steps before first run
                existing_steps = job_spec['steps']
                first_run_idx = None
                for idx, step in enumerate(existing_steps):
                    if isinstance(step, dict) and 'run' in step:
                        first_run_idx = idx
                        break
                
                if first_run_idx is not None:
                    job_spec['steps'] = new_steps + existing_steps
                else:
                    job_spec['steps'] = new_steps + existing_steps
            
            # Replace secret references in content with credential outputs
            modified_content = content
            for secret_name in secrets:
                step_id = f"cred_{secret_name.lower()}"
                old_ref = f"${{{{ secrets.{secret_name} }}}}"
                new_ref = f"${{{{ steps.{step_id}.outputs.credential }}}}"
                modified_content = modified_content.replace(old_ref, new_ref)
            
            # Add permissions to raw YAML (in case YAML dump doesn't preserve formatting)
            if 'permissions:' not in modified_content:
                # Find position after 'name:' line
                name_match = re.search(r'^name:\s*.+$', modified_content, re.MULTILINE)
                if name_match:
                    insert_pos = name_match.end()
                    permissions_yaml = "\npermissions:\n  id-token: write"
                    modified_content = modified_content[:insert_pos] + permissions_yaml + modified_content[insert_pos:]
            
            # Validate modified YAML
            try:
                yaml.safe_load(modified_content)
            except yaml.YAMLError as e:
                return False, f"Invalid modified YAML: {e}"
            
            # Write modified file
            with open(filepath, 'w') as f:
                f.write(modified_content)
            
            return True, f"Migrated {len(secrets)} secret(s): {', '.join(sorted(secrets))}"
        
        except Exception as e:
            return False, str(e)

    def migrate_batch(self, pattern: str = None, max_files: int = None, dry_run: bool = False) -> Dict:
        """
        Migrate batch of workflows matching pattern
        Returns: statistics dict
        """
        workflow_files = list(Path(self.workflow_dir).glob("*.yml"))
        
        if pattern:
            workflow_files = [f for f in workflow_files if pattern in f.name]
        
        if max_files:
            workflow_files = workflow_files[:max_files]
        
        results = {
            'total': len(workflow_files),
            'modified': 0,
            'skipped': 0,
            'failed': 0,
            'files': {}
        }
        
        for wf_file in sorted(workflow_files):
            if dry_run:
                results['files'][wf_file.name] = "DRY RUN - not modified"
                continue
            
            success, message = self.migrate_workflow(str(wf_file))
            results['files'][wf_file.name] = message
            
            if success:
                if "No secrets" in message or "skipped" in message or "auto-managed" in message:
                    results['skipped'] += 1
                    self.skipped_workflows.append(wf_file.name)
                else:
                    results['modified'] += 1
                    self.modified_workflows.append(wf_file.name)
            else:
                results['failed'] += 1
                self.failed_workflows.append((wf_file.name, message))
        
        return results

    def generate_report(self, results: Dict) -> str:
        """Generate migration report"""
        report = f"""
# Phase 5 Batch Migration Report

**Date**: {datetime.now().isoformat()}  
**Backup**: {self.backup_dir}

## Statistics

- **Total Processed**: {results['total']}
- **Modified**: {results['modified']}
- **Skipped**: {results['skipped']}
- **Failed**: {results['failed']}

## Results

### Modified Workflows ({results['modified']})
"""
        for wf in self.modified_workflows:
            report += f"- ✅ {wf}\n"
        
        if self.skipped_workflows:
            report += f"\n### Skipped ({len(self.skipped_workflows)})\n"
            for wf in self.skipped_workflows:
                report += f"- ⏭️  {wf}\n"
        
        if self.failed_workflows:
            report += f"\n### Failed ({len(self.failed_workflows)})\n"
            for wf, error in self.failed_workflows:
                report += f"- ❌ {wf}: {error}\n"
        
        return report


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Phase 5 Workflow Migration')
    parser.add_argument('--pattern', help='Filter workflows by name pattern')
    parser.add_argument('--max', type=int, help='Maximum workflows to process')
    parser.add_argument('--dry-run', action='store_true', help='Dry run (no modifications)')
    parser.add_argument('--batch', choices=['all', 'tests', 'builds', 'deploys', 'infra'], 
                       default='tests', help='Workflow batch to migrate')
    
    args = parser.parse_args()
    
    # Map batch to pattern
    batch_patterns = {
        'tests': 'test|lint|validate|check',
        'builds': 'build|compile|docker',
        'deploys': 'deploy|release',
        'infra': 'terraform|automation|vault'
    }
    
    pattern = batch_patterns.get(args.batch) if args.batch != 'all' else None
    
    migrator = WorkflowMigrator()
    results = migrator.migrate_batch(pattern=pattern, max_files=args.max, dry_run=args.dry_run)
    
    report = migrator.generate_report(results)
    print(report)
    
    # Save report
    report_file = f"phase5-migration-report-{datetime.now().strftime('%Y%m%d_%H%M%S')}.md"
    with open(report_file, 'w') as f:
        f.write(report)
    print(f"\n✅ Report saved: {report_file}")
    
    return 0 if results['failed'] == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
