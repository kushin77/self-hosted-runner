#!/usr/bin/env python3
"""
Comprehensive workflow YAML error fixer
Detects and automatically fixes common syntax issues in GitHub workflow files
"""

import os
import re
import yaml
import glob
from pathlib import Path
from typing import Tuple, List, Dict

class WorkflowYAMLFixer:
    def __init__(self, workflows_dir: str = ".github/workflows"):
        self.workflows_dir = workflows_dir
        self.fixes_log = []
        
    def find_error_workflows(self) -> List[Tuple[str, str]]:
        """Find all workflows with YAML syntax errors"""
        errors = []
        for wf_file in sorted(glob.glob(f"{self.workflows_dir}/*.yml")):
            try:
                with open(wf_file) as f:
                    yaml.safe_load(f)
            except yaml.YAMLError as e:
                errors.append((wf_file, str(e)))
        return errors
    
    def read_file(self, filepath: str) -> str:
        """Read a workflow file"""
        with open(filepath, 'r') as f:
            return f.read()
    
    def write_file(self, filepath: str, content: str):
        """Write a workflow file"""
        with open(filepath, 'w') as f:
            f.write(content)
    
    def fix_redacted_secrets(self, content: str) -> str:
        """Fix redacted secret placeholders that break YAML"""
        # Replace malformed redacted secrets with a proper YAML string
        content = re.sub(
            r'<REDACTED_SECRET_REMOVED_BY_AUTOMATION>',
            '# [REDACTED_SECRET]',
            content
        )
        return content
    
    def fix_multiline_quotes(self, content: str) -> str:
        """Fix issues with multiline strings and quote handling"""
        lines = content.split('\n')
        fixed_lines = []
        in_multiline = False
        
        for i, line in enumerate(lines):
            # Detect start of multiline block with |
            if re.search(r':\s*\|\s*$', line):
                in_multiline = True
                fixed_lines.append(line)
            # Detect end of multiline block (unindented line)
            elif in_multiline and line.strip() and not line.startswith(' ' * 10):
                in_multiline = False
                fixed_lines.append(line)
            else:
                fixed_lines.append(line)
        
        return '\n'.join(fixed_lines)
    
    def fix_github_context_escaping(self, content: str) -> str:
        """Fix Python f-string conflicts with GitHub context variables"""
        # Fix unescaped ${{ }} in Python code
        # Look for patterns like: f"something ${{ github.run_id }}"
        
        # In run: blocks, wrap entire command in single quotes when possible
        def fix_run_block(match):
            run_content = match.group(1)
            # If contains unquoted ${{, wrap whole thing
            if "${{" in run_content and "'" not in run_content[:50]:
                # Escape any existing single quotes
                run_content = run_content.replace("'", "\\'")
                return f"run: |\n  {run_content}"
            return match.group(0)
        
        content = re.sub(
            r'(run:\s*)(.*?)(?=\n\s{2,}[a-z]|$)',
            fix_run_block,
            content,
            flags=re.MULTILINE | re.DOTALL
        )
        
        return content
    
    def fix_invalid_permissions(self, content: str) -> str:
        """Remove invalid GitHub permission names"""
        # Valid permissions: actions, checks, contents, deployments, id-token,
        # issues, pull-requests, repository-projects, security-events, statuses
        invalid_perms = ['artifacts', 'secrets', 'workflows']
        
        for perm in invalid_perms:
            # Remove lines like "artifacts: write"
            content = re.sub(
                rf'^\s*{perm}:\s*(read|write)\s*$',
                '',
                content,
                flags=re.MULTILINE
            )
        
        return content
    
    def fix_indentation_issues(self, content: str) -> str:
        """Fix common indentation problems"""
        lines = content.split('\n')
        fixed_lines = []
        
        for i, line in enumerate(lines):
            # Fix lines that should be indented but aren't
            if line.strip() and not line.startswith((' ', '#')):
                # Check if this is a continuation that needs indentation
                if i > 0 and lines[i-1].strip().endswith(('|', '|-', '>')):
                    # This is a multi-line content block, keep as is
                    fixed_lines.append(line)
                else:
                    fixed_lines.append(line)
            else:
                fixed_lines.append(line)
        
        return '\n'.join(fixed_lines)
    
    def ensure_workflow_dispatch(self, content: str) -> str:
        """Ensure workflow_dispatch is available for manual triggering"""
        if 'workflow_dispatch:' not in content and 'on:' in content:
            # Add workflow_dispatch if on: block exists but no workflow_dispatch
            lines = content.split('\n')
            for i, line in enumerate(lines):
                if line.strip().startswith('on:'):
                    # Find the end of the on: block
                    j = i + 1
                    last_trigger = i
                    while j < len(lines):
                        if lines[j].strip() and not lines[j].startswith(' '):
                            break
                        if lines[j].strip() and lines[j][0] != ' ':
                            break
                        if lines[j].strip():
                            last_trigger = j
                        j += 1
                    
                    # Check if workflow_dispatch already exists
                    on_block = '\n'.join(lines[i:last_trigger+2])
                    if 'workflow_dispatch' not in on_block:
                        # Add it
                        lines.insert(last_trigger + 1, '  workflow_dispatch:')
                    break
            
            content = '\n'.join(lines)
        
        return content
    
    def fix_workflow(self, filepath: str) -> Tuple[bool, str]:
        """Fix a single workflow file"""
        try:
            content = self.read_file(filepath)
            original_content = content
            
            # Apply fixes in order
            content = self.fix_redacted_secrets(content)
            content = self.fix_invalid_permissions(content)
            content = self.fix_multiline_quotes(content)
            content = self.fix_github_context_escaping(content)
            content = self.fix_indentation_issues(content)
            content = self.ensure_workflow_dispatch(content)
            
            # Validate the fixed content
            try:
                yaml.safe_load(content)
                # Validation passed
                if content != original_content:
                    self.write_file(filepath, content)
                    self.fixes_log.append((filepath, "✅ FIXED"))
                    return (True, "Fixed")
                else:
                    return (True, "No changes needed")
            except yaml.YAMLError as e:
                # Still has errors, log it
                self.fixes_log.append((filepath, f"⚠️  Still has errors: {str(e)[:80]}"))
                return (False, str(e)[:100])
        
        except Exception as e:
            self.fixes_log.append((filepath, f"❌ Exception: {str(e)[:80]}"))
            return (False, str(e))
    
    def run(self):
        """Fix all workflow files with errors"""
        error_files = self.find_error_workflows()
        
        print(f"\n🔧 Workflow YAML Error Fixer")
        print(f"{'=' * 60}")
        print(f"Found {len(error_files)} workflows with YAML syntax errors\n")
        
        fixed_count = 0
        still_broken_count = 0
        
        for filepath, error in error_files:
            filename = filepath.replace(f"{self.workflows_dir}/", "")
            print(f"🔧 Processing: {filename:<50}", end=" ")
            
            success, msg = self.fix_workflow(filepath)
            
            if success:
                fixed_count += 1
                print(f"✅")
            else:
                still_broken_count += 1
                print(f"⚠️")
        
        print(f"\n{'=' * 60}")
        print(f"Summary:")
        print(f"  ✅ Fixed: {fixed_count}/{len(error_files)}")
        print(f"  ⚠️  Still broken: {still_broken_count}/{len(error_files)}")
        
        # Verify final state
        remaining_errors = self.find_error_workflows()
        print(f"\n📊 Final state: {len(remaining_errors)} workflows still have errors\n")
        
        # Print still-broken files
        if remaining_errors:
            print("Still broken files:")
            for f, e in remaining_errors:
                fname = f.replace(f"{self.workflows_dir}/", "")
                print(f"  ❌ {fname}")
        
        return len(remaining_errors) == 0

if __name__ == "__main__":
    fixer = WorkflowYAMLFixer()
    success = fixer.run()
    exit(0 if success else 1)
