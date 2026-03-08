#!/usr/bin/env python3
"""
Immutable Compliance Auto-Remediator

Scans GitHub Actions workflows for compliance violations and applies idempotent fixes.
Features:
  - Append-only audit trail (JSONL format)
  - Idempotent operations (safe to run repeatedly)
  - Detects: missing permissions, missing timeouts, missing job names, hardcoded secrets
  - Generates compliance report
"""

import argparse
import json
import os
import sys
import yaml
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple, Any


class ComplianceAuditor:
    """Handles workflow compliance scanning and remediation."""
    
    RESTRICTIVE_PERMISSIONS = {
        'contents': 'read',
        'pull-requests': 'read',
        'issues': 'read',
        'secrets': 'none'
    }
    
    DEFAULT_TIMEOUT_MINUTES = 30
    
    def __init__(self, workflow_dir: str, audit_dir: str):
        self.workflow_dir = Path(workflow_dir)
        self.audit_dir = Path(audit_dir)
        self.audit_dir.mkdir(parents=True, exist_ok=True)
        self.fixes_applied = []
        self.issues_found = []
        self.timestamp = datetime.utcnow().isoformat() + 'Z'
        
    def audit_log(self, action: str, file: str, details: str, severity: str = "INFO"):
        """Append immutable audit entry (JSONL format)."""
        entry = {
            'timestamp': self.timestamp,
            'action': action,
            'file': file,
            'details': details,
            'severity': severity,
            'run_id': os.getenv('GITHUB_RUN_ID', 'local')
        }
        self.fixes_applied.append(entry)
    
    def issue_log(self, issue_type: str, file: str, details: str):
        """Log compliance issues found."""
        entry = {
            'timestamp': self.timestamp,
            'type': issue_type,
            'file': file,
            'details': details
        }
        self.issues_found.append(entry)
    
    def load_workflow(self, path: Path) -> Tuple[Dict[str, Any], str]:
        """Load workflow YAML file."""
        try:
            with open(path, 'r') as f:
                content = f.read()
                workflow = yaml.safe_load(content)
                return workflow, content
        except Exception as e:
            print(f"Warning: Could not load {path}: {e}", file=sys.stderr)
            return None, ""
    
    def save_workflow(self, path: Path, workflow: Dict[str, Any]):
        """Save workflow YAML file with proper formatting."""
        try:
            with open(path, 'w') as f:
                yaml.dump(workflow, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
            return True
        except Exception as e:
            print(f"Error: Could not save {path}: {e}", file=sys.stderr)
            return False
    
    def fix_missing_permissions(self, workflow: Dict) -> bool:
        """Add restrictive default permissions if missing."""
        changed = False
        if 'permissions' not in workflow or workflow['permissions'] is None:
            workflow['permissions'] = self.RESTRICTIVE_PERMISSIONS.copy()
            changed = True
        return changed
    
    def fix_missing_timeout(self, job: Dict) -> bool:
        """Add default timeout-minutes to job if missing."""
        changed = False
        if 'timeout-minutes' not in job:
            job['timeout-minutes'] = self.DEFAULT_TIMEOUT_MINUTES
            changed = True
        return changed
    
    def fix_missing_job_names(self, workflow: Dict) -> bool:
        """Add descriptive names to jobs if missing."""
        changed = False
        if 'jobs' not in workflow:
            return changed
        
        for job_id, job in workflow['jobs'].items():
            if 'name' not in job:
                # Generate readable name from job ID
                job_name = job_id.replace('-', ' ').title()
                job['name'] = job_name
                changed = True
        return changed
    
    def check_hardcoded_secrets(self, workflow: Dict, file: str) -> List[str]:
        """Detect potential hardcoded secrets."""
        issues = []
        content_str = json.dumps(workflow)
        
        # Patterns that might indicate hardcoded secrets
        secret_patterns = [
            'password', 'token', 'secret', 'key', 'credential',
            'api_key', 'api-key', 'apikey', 'auth'
        ]
        
        for pattern in secret_patterns:
            if pattern.lower() in content_str.lower():
                # Check if it's in env vars or hardcoded strings (rough heuristic)
                if 'env:' in content_str or 'run:' in content_str:
                    issues.append(f"Potential hardcoded {pattern} detected in {file}")
        
        return issues
    
    def process_workflow(self, path: Path) -> bool:
        """Process single workflow file."""
        workflow, original_content = self.load_workflow(path)
        if workflow is None:
            return False
        
        file_rel = path.relative_to(self.workflow_dir)
        changed = False
        
        # Apply fixes
        if self.fix_missing_permissions(workflow):
            changed = True
            self.audit_log('ADD_PERMISSIONS', str(file_rel), 'Added restrictive default permissions')
        
        if 'jobs' in workflow:
            for job_id, job in workflow['jobs'].items():
                if self.fix_missing_timeout(job):
                    changed = True
                    self.audit_log('ADD_TIMEOUT', str(file_rel), f'Added timeout to job {job_id}')
        
        if self.fix_missing_job_names(workflow):
            changed = True
            self.audit_log('ADD_JOB_NAMES', str(file_rel), 'Added descriptive job names')
        
        # Check for hardcoded secrets
        secret_issues = self.check_hardcoded_secrets(workflow, str(file_rel))
        for issue in secret_issues:
            self.issue_log('HARDCODED_SECRET', str(file_rel), issue)
            self.audit_log('FLAGGED_SECRET', str(file_rel), issue, severity='WARNING')
        
        # Save if changed
        if changed:
            if self.save_workflow(path, workflow):
                return True
        
        return False
    
    def scan_workflows(self) -> Tuple[int, int]:
        """Scan all workflows in the workflows directory."""
        fixed_count = 0
        issue_count = 0
        
        if not self.workflow_dir.exists():
            print(f"Workflow directory not found: {self.workflow_dir}", file=sys.stderr)
            return 0, 0
        
        for workflow_file in self.workflow_dir.glob('*.yml'):
            if workflow_file.name.startswith('.'):
                continue
            
            if self.process_workflow(workflow_file):
                fixed_count += 1
            
            if self.issues_found:
                issue_count = len(self.issues_found)
        
        return fixed_count, issue_count
    
    def write_audit_trail(self):
        """Write immutable append-only audit trail."""
        if not self.fixes_applied:
            return
        
        audit_file = self.audit_dir / f"compliance-fixes-{self.timestamp.replace(':', '-').replace('Z', '')}.jsonl"
        try:
            with open(audit_file, 'a') as f:
                for entry in self.fixes_applied:
                    f.write(json.dumps(entry) + '\n')
            print(f"Audit trail: {audit_file}")
        except Exception as e:
            print(f"Error: Could not write audit trail: {e}", file=sys.stderr)
    
    def generate_report(self) -> str:
        """Generate compliance report."""
        report = []
        report.append("# Compliance Auto-Fixer Report")
        report.append(f"\nGenerated: {self.timestamp}")
        
        report.append(f"\n## Summary")
        report.append(f"- Fixes Applied: {len(self.fixes_applied)}")
        report.append(f"- Issues Found: {len(self.issues_found)}")
        
        if self.fixes_applied:
            report.append(f"\n## Fixes Applied")
            for entry in self.fixes_applied:
                report.append(f"- [{entry['action']}] {entry['file']}: {entry['details']}")
        
        if self.issues_found:
            report.append(f"\n## Issues Requiring Manual Review")
            for entry in self.issues_found:
                report.append(f"- [{entry['type']}] {entry['file']}: {entry['details']}")
        
        return '\n'.join(report)


def main():
    parser = argparse.ArgumentParser(description='Compliance Auto-Remediator for GitHub Actions')
    parser.add_argument('--workflow-dir', required=True, help='Directory containing workflows')
    parser.add_argument('--audit-dir', required=True, help='Directory for audit logs')
    parser.add_argument('--auto-fix', action='store_true', help='Apply fixes automatically')
    parser.add_argument('--report', help='Output report to file')
    
    args = parser.parse_args()
    
    auditor = ComplianceAuditor(args.workflow_dir, args.audit_dir)
    fixed, issues = auditor.scan_workflows()
    
    auditor.write_audit_trail()
    
    report = auditor.generate_report()
    print(report)
    
    if args.report:
        with open(args.report, 'w') as f:
            f.write(report)
    
    # Exit with non-zero if issues found
    sys.exit(1 if issues > 0 else 0)


if __name__ == '__main__':
    main()
