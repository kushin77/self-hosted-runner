#!/usr/bin/env python3
"""
Auto-remediate compliance violations in GitHub workflows.

Features:
- Idempotent: Safe to re-run multiple times
- Immutable audit trail: All fixes logged to append-only audit file
- Ephemeral: Temp files cleaned up after execution
- No-ops: Scheduled automation, fully hands-off
"""

import json
import os
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple


class ComplianceAuditor:
    """Audit and fix workflow compliance violations."""

    AUDIT_DIR = ".compliance-audit"
    DEFAULT_TIMEOUT = 30
    DEFAULT_PERMISSIONS = {"contents": "read"}
    
    def __init__(self, dry_run: bool = True, verbose: bool = False):
        """Initialize auditor."""
        self.dry_run = dry_run
        self.verbose = verbose
        self.fixes_applied = []
        self.audit_log = []
        self._ensure_audit_dir()

    def _ensure_audit_dir(self):
        """Ensure audit directory exists."""
        Path(self.AUDIT_DIR).mkdir(exist_ok=True)

    def _log_audit(self, action: str, file: str, details: dict):
        """Append immutable audit entry (append-only)."""
        entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "action": action,
            "file": file,
            "dry_run": self.dry_run,
            "details": details,
        }
        self.audit_log.append(entry)
        
        # Write to immutable audit file (append-only)
        audit_file = Path(self.AUDIT_DIR) / f"compliance-fixes-{datetime.utcnow().strftime('%Y-%m-%d')}.jsonl"
        with open(audit_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
        
        if self.verbose:
            print(f"[AUDIT] {action}: {file} -> {details}")

    def fix_missing_permissions(self, workflow_content: str, filename: str) -> Tuple[str, bool]:
        """Add missing permissions block with restrictive defaults."""
        if "permissions:" in workflow_content:
            return workflow_content, False
        
        # Find first 'jobs:' or 'env:' and insert permissions before it
        lines = workflow_content.split("\n")
        inserted = False
        result_lines = []
        
        for i, line in enumerate(lines):
            # Insert after 'on:' section
            if line.strip().startswith("on:") and (i + 1 < len(lines)) and not lines[i+1].strip().startswith("jobs:"):
                result_lines.append(line)
                # Find end of 'on:' block
                j = i + 1
                while j < len(lines) and (lines[j].startswith("  ") or lines[j].strip() == ""):
                    result_lines.append(lines[j])
                    j += 1
                # Insert permissions before jobs
                if j < len(lines) and lines[j].strip().startswith("jobs:"):
                    result_lines.append("")
                    result_lines.append("permissions:")
                    result_lines.append("  contents: read")
                    inserted = True
            else:
                result_lines.append(line)
        
        new_content = "\n".join(result_lines)
        if inserted:
            self._log_audit("fix_missing_permissions", filename, {"added": "permissions: {contents: read}"})
            self.fixes_applied.append("fix_missing_permissions")
        
        return new_content, inserted

    def fix_missing_timeout(self, workflow_content: str, filename: str) -> Tuple[str, bool]:
        """Add missing timeout-minutes to jobs."""
        if "timeout-minutes:" in workflow_content:
            return workflow_content, False
        
        lines = workflow_content.split("\n")
        result_lines = []
        changed = False
        in_jobs = False
        job_indent = 0
        
        for i, line in enumerate(lines):
            if line.strip().startswith("jobs:"):
                in_jobs = True
                result_lines.append(line)
                continue
            
            if in_jobs and line.strip() and not line.startswith("  "):
                in_jobs = False
            
            # Detect job definition lines (e.g., "  my-job:")
            if in_jobs and re.match(r"^  \w+:\s*$", line):
                result_lines.append(line)
                job_indent = len(line) - len(line.lstrip())
                # Check if next non-empty line is timeout-minutes
                j = i + 1
                while j < len(lines) and lines[j].strip() == "":
                    result_lines.append(lines[j])
                    j += 1
                
                if j < len(lines) and not lines[j].startswith(" " * (job_indent + 2) + "timeout-minutes:"):
                    # Insert timeout-minutes
                    result_lines.append(" " * (job_indent + 2) + "timeout-minutes: 30")
                    self._log_audit("fix_missing_timeout", filename, {"added": "timeout-minutes: 30"})
                    self.fixes_applied.append("fix_missing_timeout")
                    changed = True
                continue
            
            result_lines.append(line)
        
        new_content = "\n".join(result_lines)
        return new_content, changed

    def fix_missing_job_names(self, workflow_content: str, filename: str) -> Tuple[str, bool]:
        """Add human-readable names to jobs via 'name:' field."""
        lines = workflow_content.split("\n")
        result_lines = []
        changed = False
        in_jobs = False
        
        for i, line in enumerate(lines):
            if line.strip().startswith("jobs:"):
                in_jobs = True
                result_lines.append(line)
                continue
            
            if in_jobs and line.strip() and not line.startswith("  "):
                in_jobs = False
            
            # Detect job definition (e.g., "  build:")
            if in_jobs and re.match(r"^  ([a-z0-9_-]+):\s*$", line):
                result_lines.append(line)
                job_name = re.match(r"^  ([a-z0-9_-]+):\s*$", line).group(1)
                
                # Check if next non-empty line has 'name:'
                j = i + 1
                while j < len(lines) and lines[j].strip() == "":
                    result_lines.append(lines[j])
                    j += 1
                
                if j < len(lines) and not lines[j].strip().startswith("name:"):
                    # Add human-readable name
                    friendly_name = job_name.replace("-", " ").title()
                    result_lines.append("    name: " + friendly_name)
                    self._log_audit("fix_missing_job_names", filename, {"job": job_name, "added_name": friendly_name})
                    self.fixes_applied.append("fix_missing_job_names")
                    changed = True
                continue
            
            result_lines.append(line)
        
        new_content = "\n".join(result_lines)
        return new_content, changed

    def fix_hardcoded_secrets(self, workflow_content: str, filename: str) -> Tuple[str, bool]:
        """Detect hardcoded secret patterns and flag for user action (cannot auto-fix)."""
        # Regex patterns for common secret formats
        patterns = {
            "aws_key": r"AKIA[0-9A-Z]{16}",
            "gcp_key": r"-----BEGIN RSA PRIVATE KEY-----",
            "api_token": r"(token|api[_-]?key|secret)[\":\s=]+([a-zA-Z0-9\-_.]{20,})",
        }
        
        found_secrets = []
        for secret_type, pattern in patterns.items():
            if re.search(pattern, workflow_content):
                found_secrets.append(secret_type)
                self._log_audit("hardcoded_secrets_detected", filename, {"secret_type": secret_type, "action": "MANUAL_REVIEW_REQUIRED"})
        
        return workflow_content, len(found_secrets) > 0

    def process_workflow(self, filepath: Path) -> Dict:
        """Process a single workflow file."""
        if not filepath.suffix == ".yml" and not filepath.suffix == ".yaml":
            return {"file": str(filepath), "skipped": True, "reason": "not YAML"}
        
        try:
            with open(filepath, "r") as f:
                original_content = f.read()
        except Exception as e:
            return {"file": str(filepath), "error": str(e)}
        
        content = original_content
        changes = []
        
        # Apply fixes
        content, changed = self.fix_missing_permissions(content, str(filepath))
        if changed:
            changes.append("permissions")
        
        content, changed = self.fix_missing_timeout(content, str(filepath))
        if changed:
            changes.append("timeout")
        
        content, changed = self.fix_missing_job_names(content, str(filepath))
        if changed:
            changes.append("job_names")
        
        content, changed = self.fix_hardcoded_secrets(content, str(filepath))
        if changed:
            changes.append("hardcoded_secrets_review_needed")
        
        # Write changes if not dry-run
        if not self.dry_run and content != original_content:
            with open(filepath, "w") as f:
                f.write(content)
            self._log_audit("workflow_updated", str(filepath), {"fixes": changes})
        elif content != original_content:
            self._log_audit("workflow_would_be_updated", str(filepath), {"fixes": changes, "dry_run": True})
        
        return {
            "file": str(filepath),
            "changes": changes,
            "changed": content != original_content,
            "dry_run": self.dry_run,
        }

    def scan_workflows(self, workflow_dir: Path = Path(".github/workflows")) -> List[Dict]:
        """Scan all workflows in directory."""
        if not workflow_dir.exists():
            return []
        
        results = []
        for workflow_file in workflow_dir.glob("*.yml") + workflow_dir.glob("*.yaml"):
            result = self.process_workflow(workflow_file)
            results.append(result)
        
        return results

    def generate_report(self) -> str:
        """Generate summary report."""
        report = f"""
# Compliance Auto-Remediation Report
**Generated:** {datetime.utcnow().isoformat()}Z
**Dry Run:** {self.dry_run}
**Fixes Applied:** {len(self.fixes_applied)}

## Audit Trail
All changes logged to: `.compliance-audit/compliance-fixes-*.jsonl`

## Fixes Summary
"""
        for fix in set(self.fixes_applied):
            report += f"- {fix}\n"
        
        return report


def main():
    """Main entry point."""
    dry_run = os.getenv("DRY_RUN", "true").lower() == "true"
    verbose = os.getenv("VERBOSE", "false").lower() == "true"
    
    auditor = ComplianceAuditor(dry_run=dry_run, verbose=verbose)
    results = auditor.scan_workflows()
    
    print(auditor.generate_report())
    print(json.dumps(results, indent=2))
    
    # Exit with success if any fixes were needed
    if any(r.get("changed") for r in results):
        print(f"✓ Processed {len(results)} workflows")
        return 0
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
