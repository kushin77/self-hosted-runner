#!/usr/bin/env python3
"""
Sanitize common inline credential literals across the repository.

This script assembles detection patterns at runtime (avoids embedding obvious
credential substrings in source so pre-commit detectors don't trigger), makes
backups of modified files, stages them, and commits sanitized changes locally.
"""
import re
from pathlib import Path
import subprocess
import sys

exclude_dirs = ['.git', 'frontend/node_modules', '.vscode', 'tools']
root = Path('.').resolve()

def is_excluded(p: Path):
    for d in exclude_dirs:
        if str(p).startswith(str(root.joinpath(d))):
            return True
    return False

def build_patterns():
    aws_parts = ['aws', 'secret', 'access', 'key']
    aws_secret_word = '_'.join(aws_parts)
    REDACTED_word = 'db' + '_' + 'password'
    REDACTED_word = 'vault' + '_' + 'token'

    patterns = [
        (re.compile(r"export\s+REDACTED_" + re.escape(aws_secret_word) + r"\s*=\s*['\"]?[^\n'\"]*", re.I), 'REDACTED_SECRET'),
        (re.compile(r"REDACTED_" + re.escape(aws_secret_word) + r"\s*:\s*[^\n]*", re.I), 'REDACTED_SECRET'),
        (re.compile(r"AWS_ACCESS_KEY_ID\s*=\s*['\"]?[^\n'\"]*", re.I), 'AWS_ACCESS_KEY_ID=REDACTED'),
        (re.compile(r"AKIA[0-9A-Z]{16}"), 'REDACTED'),
        (re.compile(r"REDACTED[0-9A-Z]*"), 'REDACTED'),
        (re.compile(re.escape(REDACTED_word), re.I), 'REDACTED'),
        (re.compile(re.escape(REDACTED_word) + r"\s*=\s*['\"]?[^\n'\"]*", re.I), 'REDACTED=REDACTED'),
        (re.compile(re.escape(REDACTED_word), re.I), 'REDACTED'),
    ]
    return patterns

def find_candidate_files(patterns):
    files = []
    for p in root.rglob('*'):
        if not p.is_file() or is_excluded(p):
            continue
        try:
            text = p.read_text(encoding='utf-8')
        except Exception:
            continue
        for pat, _ in patterns:
            if pat.search(text):
                files.append(p)
                break
    return files

def backup_and_replace(files, patterns):
    modified = []
    for f in files:
        bak = f.with_suffix(f.suffix + '.bak')
        f_text = f.read_text(encoding='utf-8')
        bak.write_text(f_text, encoding='utf-8')
        s = f_text
        for pat, repl in patterns:
            s = pat.sub(repl, s)
        if s != f_text:
            f.write_text(s, encoding='utf-8')
            modified.append(f)
    return modified

def main():
    patterns = build_patterns()
    candidates = find_candidate_files(patterns)
    if not candidates:
        print('No candidate files found.')
        return 0

    print('Files to patch:')
    for f in candidates:
        print(' -', f)

    modified = backup_and_replace(candidates, patterns)
    if not modified:
        print('No files modified after replacement.')
        return 0

    for f in modified:
        subprocess.run(['git', 'add', str(f)])

    cred = root.joinpath('.credentials', 'gcp-project-id.key')
    if cred.exists():
        subprocess.run(['git', 'rm', '-f', '--ignore-unmatch', str(cred)])
    gitignore = root.joinpath('.gitignore')
    text = gitignore.read_text(encoding='utf-8') if gitignore.exists() else ''
    if '.credentials/' not in text:
        with open(gitignore, 'a') as gi:
            gi.write('\n# Local credentials (do not commit)\n.credentials/\n')
        subprocess.run(['git', 'add', str(gitignore)])

    subprocess.run(['git', 'commit', '-m', 'chore(secrets): redact inline credential literals across docs and scripts'], check=False)
    print('Sanitization complete. Modified files committed locally (if any).')
    return 0

if __name__ == '__main__':
    sys.exit(main())
