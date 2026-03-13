#!/usr/bin/env python3
"""
Secret Sprawl Detection Mechanism for Pre-commit Hooks
Detects unauthorized secret storage patterns and proliferation across the codebase.
"""

import re
import sys
import json
import subprocess
from pathlib import Path
from typing import List, Dict, Set, Tuple
from datetime import datetime
import argparse

# Secret pattern definitions
SECRET_PATTERNS = {
    "aws_access_key": {
        "pattern": r"AKIA[0-9A-Z]{16}",
        "severity": "CRITICAL",
        "description": "AWS Access Key ID"
    },
    "aws_secret_key": {
        "pattern": r"aws_secret_access_key\s*[=:]\s*['\"]?([A-Za-z0-9/+=]{40})['\"]?",
        "severity": "CRITICAL",
        "description": "AWS Secret Access Key"
    },
    "vault_token": {
        "pattern": r"hvs\.[a-zA-Z0-9_-]{90,}",
        "severity": "CRITICAL",
        "description": "Vault Service Token"
    },
    "github_token": {
        "pattern": r"gh[pousr]_[A-Za-z0-9_]{36,255}",
        "severity": "CRITICAL",
        "description": "GitHub Token"
    },
    "private_key_pem": {
        "pattern": r"-----BEGIN (?:RSA|DSA|EC|PGP|OPENSSH|PRIVATE) KEY-----",
        "severity": "CRITICAL",
        "description": "Private Key (PEM format)"
    },
    "gcp_service_account": {
        "pattern": r'"type":\s*"service_account"',
        "severity": "CRITICAL",
        "description": "GCP Service Account Key"
    },
    "database_password": {
        "pattern": r"(?:password|passwd|pwd)\s*[=:]\s*['\"]([^'\"]+)['\"]",
        "severity": "HIGH",
        "description": "Database Password"
    },
    "api_key": {
        "pattern": r"(?:api[_-]?key|apikey)\s*[=:]\s*['\"]([^'\"]+)['\"]",
        "severity": "HIGH",
        "description": "API Key"
    },
    "connection_string": {
        "pattern": r"(?:Server|Host)=.*(?:Password|pwd)=([^;\"]+)",
        "severity": "HIGH",
        "description": "Connection String with Credentials"
    },
    "oauth_token": {
        "pattern": r"(?:access_token|refresh_token)\s*[=:]\s*['\"]([^'\"]+)['\"]",
        "severity": "HIGH",
        "description": "OAuth Token"
    }
}

# File patterns to exclude from scanning
EXCLUDE_PATTERNS = [
    r"\.git/",
    r"\.env\.example",
    r"node_modules/",
    r"\.venv/",
    r"venv/",
    r"\.pytest_cache/",
    r"\.mypy_cache/",
    r"dist/",
    r"build/",
    r"__pycache__/",
    r"\.secrets\.baseline",
    r"coverage/",
    r"\.jpg$",
    r"\.png$",
    r"\.gif$",
    r"\.zip$",
    r"\.tar\.gz$",
    r"\.whl$",
    r"tests/fixtures/",
    r"docs/examples/",
]


class SecretSprawlDetector:
    """Detects and reports secret sprawl across the codebase."""
    
    def __init__(self, repo_path: str = ".", baseline_file: str = None):
        self.repo_path = Path(repo_path)
        self.baseline_file = baseline_file
        self.findings: List[Dict] = []
        self.baseline: Dict = self._load_baseline()
        
    def _load_baseline(self) -> Dict:
        """Load baseline of known/approved secrets."""
        if self.baseline_file and Path(self.baseline_file).exists():
            try:
                with open(self.baseline_file, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Warning: Could not load baseline: {e}", file=sys.stderr)
        return {"verified_secrets": {}, "excluded_locations": []}
    
    def should_exclude(self, file_path: str) -> bool:
        """Check if file should be excluded from scanning."""
        for pattern in EXCLUDE_PATTERNS:
            if re.search(pattern, file_path):
                return True
        return False
    
    def is_baseline_approved(self, file_path: str, finding: Dict) -> bool:
        """Check if finding is in baseline as approved."""
        key = f"{file_path}:{finding['line_number']}:{finding['pattern_name']}"
        return key in self.baseline.get("verified_secrets", {})
    
    def scan_file(self, file_path: Path) -> List[Dict]:
        """Scan a single file for secrets."""
        findings = []
        
        try:
            content = file_path.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            return findings
        
        for line_num, line in enumerate(content.split('\n'), 1):
            for pattern_name, pattern_config in SECRET_PATTERNS.items():
                matches = re.finditer(pattern_config["pattern"], line, re.IGNORECASE)
                for match in matches:
                    finding = {
                        "file": str(file_path.relative_to(self.repo_path)),
                        "line_number": line_num,
                        "line_preview": line[:80].strip(),
                        "pattern_name": pattern_name,
                        "description": pattern_config["description"],
                        "severity": pattern_config["severity"],
                        "match": match.group(0)[:50]  # Truncate for safety
                    }
                    
                    if not self.is_baseline_approved(str(file_path), finding):
                        findings.append(finding)
        
        return findings
    
    def scan_repository(self, staged_only: bool = True) -> List[Dict]:
        """Scan repository for secrets."""
        if staged_only:
            files = self._get_staged_files()
        else:
            files = self._get_all_files()
        
        for file_path in files:
            if self.should_exclude(str(file_path)):
                continue
            
            file_findings = self.scan_file(file_path)
            self.findings.extend(file_findings)
        
        return self.findings
    
    def _get_staged_files(self) -> List[Path]:
        """Get staged files from git."""
        try:
            result = subprocess.run(
                ["git", "diff", "--cached", "--name-only"],
                capture_output=True,
                text=True,
                cwd=self.repo_path
            )
            files = [self.repo_path / f for f in result.stdout.strip().split('\n') if f]
            return [f for f in files if f.exists()]
        except Exception:
            return []
    
    def _get_all_files(self) -> List[Path]:
        """Get all tracked files from git."""
        try:
            result = subprocess.run(
                ["git", "ls-files"],
                capture_output=True,
                text=True,
                cwd=self.repo_path
            )
            files = [self.repo_path / f for f in result.stdout.strip().split('\n') if f]
            return [f for f in files if f.exists()]
        except Exception:
            return []
    
    def report_findings(self, output_format: str = "text") -> str:
        """Generate report of findings."""
        if not self.findings:
            return "✓ No secrets detected"
        
        if output_format == "json":
            return json.dumps({
                "scan_time": datetime.now().isoformat(),
                "total_findings": len(self.findings),
                "findings": self.findings
            }, indent=2)
        
        # Text format
        critical = [f for f in self.findings if f["severity"] == "CRITICAL"]
        high = [f for f in self.findings if f["severity"] == "HIGH"]
        
        report = f"""
Secret Sprawl Detection Report
==============================
Scan Time: {datetime.now().isoformat()}
Total Findings: {len(self.findings)}

CRITICAL ({len(critical)}):
"""
        for finding in critical:
            report += f"  - {finding['file']}:{finding['line_number']} - {finding['description']}\n"
        
        if high:
            report += f"\nHIGH ({len(high)}):\n"
            for finding in high:
                report += f"  - {finding['file']}:{finding['line_number']} - {finding['description']}\n"
        
        return report
    
    def get_sprawl_metrics(self) -> Dict:
        """Calculate sprawl metrics."""
        unique_files = len(set(f["file"] for f in self.findings))
        critical_count = len([f for f in self.findings if f["severity"] == "CRITICAL"])
        high_count = len([f for f in self.findings if f["severity"] == "HIGH"])
        
        return {
            "total_findings": len(self.findings),
            "affected_files": unique_files,
            "critical_count": critical_count,
            "high_count": high_count,
            "sprawl_index": (len(self.findings) / max(unique_files, 1)) * 100
        }


def main():
    parser = argparse.ArgumentParser(description="Detect secret sprawl in repository")
    parser.add_argument("--baseline", help="Path to baseline file", default=".secrets.baseline")
    parser.add_argument("--staged", action="store_true", default=True, help="Scan only staged files")
    parser.add_argument("--all", action="store_true", help="Scan all files")
    parser.add_argument("--json", action="store_true", help="Output in JSON format")
    parser.add_argument("--metrics", action="store_true", help="Show sprawl metrics")
    
    args = parser.parse_args()
    
    detector = SecretSprawlDetector(baseline_file=args.baseline if args.baseline else None)
    staged_only = not args.all
    
    detector.scan_repository(staged_only=staged_only)
    
    if args.json:
        print(detector.report_findings(output_format="json"))
    else:
        print(detector.report_findings(output_format="text"))
    
    if args.metrics:
        metrics = detector.get_sprawl_metrics()
        print(f"\nMetrics: {json.dumps(metrics, indent=2)}")
    
    # Exit with error if critical secrets found
    if any(f["severity"] == "CRITICAL" for f in detector.findings):
        sys.exit(1)
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
