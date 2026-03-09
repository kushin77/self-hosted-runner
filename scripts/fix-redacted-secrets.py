#!/usr/bin/env python3
"""
Advanced YAML error fixer targeting redacted secret placeholders
Focuses on fixing the core issue that broke 22+ workflows
"""

import os
import re
import yaml
import glob
from pathlib import Path

class RedactedSecretFixer:
    def __init__(self, workflows_dir: str = ".github/workflows"):
        self.workflows_dir = workflows_dir
        self.fixed_files = []
        
    def fix_workflow(self, filepath: str) -> bool:
        """Fix a single workflow file by removing/replacing redacted placeholders"""
        try:
            with open(filepath, 'r') as f:
                lines = f.readlines()
            
            original_lines = lines[:]
            fixed_lines = []
            i = 0
            
            while i < len(lines):
                line = lines[i]
                
                # Strategy 1: If line is just a redacted placeholder, remove it
                if re.match(r'^\s*<REDACTED_SECRET_REMOVED_BY_AUTOMATION>\s*$', line):
                    # Skip this line entirely
                    i += 1
                    continue
                
                # Strategy 2: If redacted string is at end of line, remove it
                if '<REDACTED_SECRET_REMOVED_BY_AUTOMATION>' in line:
                    # Replace with a valid shell comment or string
                    matched = re.search(r'<REDACTED_SECRET_REMOVED_BY_AUTOMATION>', line)
                    if matched:
                        # Try to determine context
                        line_stripped = line[:matched.start()].rstrip()
                        
                        # If this appears to be in an echo or statement, replace with safe value
                        if 'echo' in line or '|' in line[:matched.start()]:
                            line = line_stripped + ' # [REDACTED_SECRET]\n'
                        elif line_stripped.endswith('=') or line_stripped.endswith((':',)):
                            # Assignment or dict key
                            line = line_stripped + ' "***REDACTED***"\n'
                        else:
                            line = line_stripped + ' # redacted\n'
                
                fixed_lines.append(line)
                i += 1
            
            # Validate fixed content
            fixed_content = ''.join(fixed_lines)
            try:
                yaml.safe_load(fixed_content)
                # Validation passed - write file
                if fixed_content != ''.join(original_lines):
                    with open(filepath, 'w') as f:
                        f.write(fixed_content)
                    self.fixed_files.append(filepath)
                    return True
                return False
            except yaml.YAMLError:
                # Still broken, don't write
                return False
                
        except Exception as e:
            print(f"Error processing {filepath}: {e}")
            return False
    
    def run(self):
        """Fix all broken workflow files"""
        # Find all broken workflows
        broken_workflows = []
        for wf_file in sorted(glob.glob(f"{self.workflows_dir}/*.yml")):
            try:
                with open(wf_file) as f:
                    yaml.safe_load(f)
            except yaml.YAMLError:
                broken_workflows.append(wf_file)
        
        print(f"\n🔧 Advanced YAML Error Fixer - Redacted Secret Removal")
        print(f"{'=' * 70}")
        print(f"Found {len(broken_workflows)} broken workflows\n")
        
        fixed_count = 0
        for wf in broken_workflows:
            name = wf.replace(f"{self.workflows_dir}/", "")
            print(f"Fixing: {name:<50}", end=" ")
            
            if self.fix_workflow(wf):
                print("✅")
                fixed_count += 1
            else:
                print("⚠️  (still broken)")
        
        print(f"\n{'=' * 70}")
        print(f"Fixed: {fixed_count}/{len(broken_workflows)}\n")
        
        # Verify
        remaining_broken = []
        for wf_file in sorted(glob.glob(f"{self.workflows_dir}/*.yml")):
            try:
                with open(wf_file) as f:
                    yaml.safe_load(f)
            except yaml.YAMLError:
                remaining_broken.append(wf_file)
        
        print(f"Final state: {len(remaining_broken)}/{len(broken_workflows)} still broken")
        
        if remaining_broken:
            print("\nStill broken:")
            for f in remaining_broken:
                print(f"  - {f.replace(self.workflows_dir + '/', '')}")
        
        return len(remaining_broken) == 0

if __name__ == "__main__":
    fixer = RedactedSecretFixer()
    success = fixer.run()
    exit(0 if success else 1)
