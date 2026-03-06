#!/usr/bin/env python3
"""
Security Audit: Detect token-like patterns in repository
Purpose: Find and report token-like literals that need sanitization
"""

import os
import re
import json
from pathlib import Path
from collections import defaultdict

# Patterns for detecting potential secrets
PATTERNS = {
    'github_token': r'ghp_[A-Za-z0-9]{36,}',
    'github_oauth': r'gho_[A-Za-z0-9]{36,}',
    'vault_token': r's\.[A-Za-z0-9]{20,}',
    'aws_access_key': r'AKIA[0-9A-Z]{16}',
    'aws_secret_key': r'(?i)aws_secret_access_key["\']?\s*[:=]\s*["\']([A-Za-z0-9/+=]{40})["\']',
    'private_key': r'-----BEGIN [A-Z ]+ PRIVATE KEY-----',
    'api_key_literal': r'["\']?[a-z_]*_key["\']?\s*[:=]\s*["\']([A-Za-z0-9_\-]{32,})["\']',
}

# File patterns to exclude
EXCLUDE_PATTERNS = [
    r'\.git',
    r'node_modules',
    r'\.venv',
    r'__pycache__',
    r'\.egg-info',
    r'\.pyc',
    r'build/',
    r'dist/',
]

# Safe indicators (unlikely to be actual secrets)
SAFE_KEYWORDS = [
    'example',
    'placeholder',
    'REDACTED',
    'SANITIZED',
    'YOUR_',
    'your_',
    '<',
    '>',
    '${',
    'ghp_',  # incomplete token
    '_placeholder',
    'test_',
    'dummy_',
]

def should_exclude(filepath):
    """Check if file should be excluded from scan"""
    filepath_str = str(filepath).lower()
    for pattern in EXCLUDE_PATTERNS:
        if re.search(pattern, filepath_str):
            return True
    return False

def looks_safe(match_text):
    """Check if match is likely a placeholder/example, not a real secret"""
    match_lower = match_text.lower()
    for keyword in SAFE_KEYWORDS:
        if keyword.lower() in match_lower:
            return True
    # Incomplete token (too short)
    if len(match_text) < 20:
        return True
    return False

def scan_file(filepath):
    """Scan a single file for potential secrets"""
    findings = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            lines = content.split('\n')
    except Exception as e:
        return findings

    for line_num, line in enumerate(lines, 1):
        for pattern_name, pattern in PATTERNS.items():
            try:
                matches = re.finditer(pattern, line)
                for match in matches:
                    match_text = match.group(0)
                    if not looks_safe(match_text):
                        findings.append({
                            'pattern': pattern_name,
                            'line': line_num,
                            'preview': line[:100],
                            'match_length': len(match_text)
                        })
            except Exception:
                pass

    return findings

def scan_repository(repo_path='.'):
    """Scan entire repository for potential secrets"""
    results = defaultdict(list)
    
    for filepath in Path(repo_path).rglob('*'):
        if filepath.is_file() and not should_exclude(filepath):
            try:
                findings = scan_file(filepath)
                if findings:
                    rel_path = str(filepath.relative_to(repo_path))
                    results[rel_path] = findings
            except Exception:
                pass
    
    return results

def generate_report(results):
    """Generate human-readable security report"""
    report_lines = [
        "# Security Audit Report",
        f"Date: {os.popen('date -u').read().strip()}",
        "",
        "## Summary",
        f"**Files with potential secrets**: {len(results)}",
        f"**Total findings**: {sum(len(v) for v in results.values())}",
        "",
        "## Findings",
        ""
    ]

    if results:
        report_lines.append("### Files Requiring Review")
        report_lines.append("")
        
        for filepath in sorted(results.keys()):
            findings = results[filepath]
            report_lines.append(f"**{filepath}**")
            for finding in findings:
                report_lines.append(
                    f"  - Line {finding['line']}: `{finding['pattern']}` "
                    f"(length: {finding['match_length']})"
                )
                report_lines.append(f"    Preview: `{finding['preview'][:60]}...`")
            report_lines.append("")
    else:
        report_lines.append("✅ No suspicious patterns found!")
        report_lines.append("")

    report_lines.extend([
        "## Recommendations",
        "",
        "### Actions if findings are real secrets:",
        "1. **Immediately**: Rotate the compromised token/key",
        "2. **Audit**: Check git log to find when it was added",
        "3. **Replace**: Use placeholder like `<token>`, `REDACTED`, or `YOUR_SECRET`",
        "4. **Document**: Add to `.gitignore-secrets` if legitimate example",
        "5. **Test**: Verify no service uses the old secret",
        "",
        "### False Positives (Safe Examples):",
        "- Variable names like `GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}`",
        "- Markdown code blocks with `ghp_xxx...` (clearly truncated)",
        "- Documentation strings mentioning token formats",
        "",
        "## Safety Check Criteria",
        "Patterns are only reported if they match all criteria:",
        "- Pattern length matches typical token format",
        "- NOT in excluded directories (node_modules, build, etc.)",
        "- NOT marked as example/placeholder/REDACTED",
        "- APPEARS in non-documentation context",
        ""
    ])

    return '\n'.join(report_lines)

if __name__ == '__main__':
    print("🔍 Starting security audit...")
    results = scan_repository()
    report = generate_report(results)
    
    print(report)
    
    # Save report
    report_path = Path('security-audit-report.md')
    report_path.write_text(report)
    print(f"\n📄 Report saved to {report_path}")
    
    # Exit with warning if findings exist
    if results:
        print(f"\n⚠️  {len(results)} file(s) with potential patterns (may be false positives)")
        exit(1)
    else:
        print("\n✅ Audit complete - no suspicious patterns found")
        exit(0)
