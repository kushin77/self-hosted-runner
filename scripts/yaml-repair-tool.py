#!/usr/bin/env python3
"""
Automatic YAML Syntax Repair Tool
Fixes all malformed workflow YAML files in batch
"""

import yaml
import re
import sys
from pathlib import Path
from typing import Tuple

class YAMLRepairTool:
    """Repair common YAML syntax errors automatically"""
    
    @staticmethod
    def diagnose(filepath: Path) -> Tuple[bool, str]:
        """Test if file is valid YAML"""
        try:
            with open(filepath) as f:
                yaml.safe_load(f)
            return True, "Valid"
        except yaml.YAMLError as e:
            return False, str(e)
    
    @staticmethod
    def repair(filepath: Path) -> Tuple[bool, str]:
        """Attempt to repair YAML file"""
        with open(filepath) as f:
            content = f.read()
        
        original = content
        
        # FIX 1: Remove YAML anchors/aliases that cause errors
        # Pattern: &alias or *alias in invalid contexts
        content = re.sub(r'&[a-zA-Z0-9_-]+\s+', '', content)
        content = re.sub(r'\*[a-zA-Z0-9_-]+', '{}', content)
        
        # FIX 2: Fix indentation of nested block mappings
        # Looks for lines that should be at root level of steps
        lines = content.split('\n')
        fixed_lines = []
        i = 0
        while i < len(lines):
            line = lines[i]
            # If we see a step definition nested under a run: block, fix indentation
            if ('- name:' in line or '- uses:' in line) and i > 0:
                # Check if previous lines end with run: block
                prev_line = lines[i-1] if i > 0 else ''
                # Ensure proper indentation (should start with 6 spaces for step level)
                if not line.startswith('      - '):
                    line = '      - ' + line.lstrip('- ')
            fixed_lines.append(line)
            i += 1
        
        content = '\n'.join(fixed_lines)
        
        # FIX 3: Fix mapping errors - ensure proper YAML structure
        # Look for lines with colons that aren't in strings
        content = re.sub(r':\s+\[', ':\n        - ', content)
        
        # FIX 4: Ensure block scalars end properly
        # If we have a run: | followed by content, ensure proper spacing
        content = re.sub(r'(run:\s+\|\s+\n)((?:.*\n)*?)(\s+- name:)', 
                        r'\1\2\n      \3', content)
        
        # Try to parse
        try:
            yaml.safe_load(content)
            if content != original:
                # Write repaired file
                with open(filepath, 'w') as f:
                    f.write(content)
                return True, "Repaired and saved"
            else:
                return False, "No changes made"
        except Exception as e:
            return False, f"Repair failed: {str(e)[:100]}"
    
    @staticmethod
    def validate_and_repair_batch(workflows_dir: Path = None):
        """Repair all workflows in batch"""
        if workflows_dir is None:
            workflows_dir = Path('.github/workflows')
        
        results = {
            'valid': [],
            'repaired': [],
            'still_broken': []
        }
        
        for wf_file in sorted(workflows_dir.glob('*.yml')):
            is_valid, msg = YAMLRepairTool.diagnose(wf_file)
            
            if is_valid:
                results['valid'].append(wf_file.name)
                print(f"✅ {wf_file.name}")
            else:
                # Try to repair
                repaired, repair_msg = YAMLRepairTool.repair(wf_file)
                if repaired and YAMLRepairTool.diagnose(wf_file)[0]:
                    results['repaired'].append((wf_file.name, repair_msg))
                    print(f"🔧 {wf_file.name} - {repair_msg}")
                else:
                    results['still_broken'].append((wf_file.name, msg[:80]))
                    print(f"❌ {wf_file.name} - {msg[:80]}")
        
        return results


if __name__ == '__main__':
    print("🔧 Automatic YAML Repair Tool\n")
    
    tool = YAMLRepairTool()
    results = tool.validate_and_repair_batch()
    
    print(f"\n{'='*70}")
    print(f"✅ Valid workflows: {len(results['valid'])}")
    print(f"🔧 Repaired: {len(results['repaired'])}")
    print(f"❌ Still broken: {len(results['still_broken'])}")
    
    if results['still_broken']:
        print(f"\n⚠️  Workflows requiring manual review:")
        for fname, err in results['still_broken']:
            print(f"  - {fname}: {err}")
        sys.exit(1)
    else:
        print(f"\n✅ ALL WORKFLOWS REPAIRED!")
        sys.exit(0)
