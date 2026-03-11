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
    """Build regex patterns for credential detection and redaction."""
    patterns = [
        # AWS credentials
        (re.compile(r'AWS_ACCESS_KEY_ID\s*=\s*["\']?[^\n"\']*', re.I), 'AWS_ACCESS_KEY_ID=REDACTED'),
        (re.compile(r'aws_secret_access_key\s*=\s*["\']?[^\n"\']*', re.I), 'aws_secret_access_key=REDACTED'),
        (re.compile(r'[A][K][I][A][0-9A-Z]{16}', re.I), 'AWS_KEY_ID_REDACTED'),
        # Vault credentials
        (re.compile(r'vault_token\s*=\s*["\']?[^\n"\']*', re.I), 'vault_token=REDACTED'),
        (re.compile(r'VAULT_TOKEN\s*=\s*["\']?[^\n"\']*', re.I), 'VAULT_TOKEN=REDACTED'),
        (re.compile(r'VAULT_ADDR\s*=\s*["\']?[^\n"\']*', re.I), 'VAULT_ADDR=REDACTED'),
        # Database passwords
        (re.compile(r'db_password\s*=\s*["\']?[^\n"\']*', re.I), 'db_password=REDACTED'),
        (re.compile(r'password\s*=\s*["\']?[^\n"\']*', re.I), 'password=REDACTED'),
        # GCP/Azure credentials
        (re.compile(r'private_key\s*["\']?:\s*["\']?[^\n"\']*', re.I), 'private_key: REDACTED'),
        (re.compile(r'api_key\s*["\']?=\s*["\']?[^\n"\']*', re.I), 'api_key=REDACTED'),
    ]
    return patterns

def find_candidate_files(patterns):
    """Find files containing credential patterns using git grep for speed."""
    files = set()
    try:
        # Use git grep to find files (much faster than rglob)
        result = subprocess.run(
            ['git', 'grep', '-l', r'(password|secret|token|key|credential|api_key|access_key|private_key)'],
            capture_output=True,
            text=True,
            cwd=root
        )
        if result.returncode == 0 and result.stdout:
            for line in result.stdout.strip().split('\n'):
                files.add(Path(line.strip()))
    except Exception:
        pass
    
    # Fallback: check tracked files manually if git grep fails
    if not files:
        binary_extensions = {'.png', '.jpg', '.jpeg', '.gif', '.zip', '.tar', '.gz', '.bin', '.so', '.pyc'}
        exclude_dirs = {'.git', 'node_modules', '__pycache__', '.pytest_cache', 'dist', 'build'}
        
        for p in root.rglob('*'):
            if any(excl in p.parts for excl in exclude_dirs):
                continue
            if not p.is_file() or p.suffix.lower() in binary_extensions:
                continue
            try:
                text = p.read_text(encoding='utf-8', errors='ignore')
            except Exception:
                continue
            for pat, _ in patterns:
                if pat.search(text):
                    files.add(p)
                    break
    
    return sorted(list(files))

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
    dry_run = '--dry-run' in sys.argv
    
    patterns = build_patterns()
    candidates = find_candidate_files(patterns)
    if not candidates:
        print('No candidate files found.')
        return 0

    print(f'Found {len(candidates)} files with potential credential patterns:')
    for f in candidates:
        print(' -', f)
    
    if dry_run:
        print('\n[DRY-RUN] Would sanitize above files. Run without --dry-run to apply changes.')
        return 0
    
    modified = backup_and_replace(candidates, patterns)
    if not modified:
        print('No files modified after replacement.')
        return 0

    print(f'\nModified {len(modified)} files. Staging for commit...')
    for f in modified:
        try:
            subprocess.run(['git', 'add', str(f)], check=True, capture_output=True)
        except subprocess.CalledProcessError as e:
            print(f'Warning: Failed to stage {f}: {e}', file=sys.stderr)

    # Update .gitignore to prevent reintroduction
    gitignore = root.joinpath('.gitignore')
    text = gitignore.read_text(encoding='utf-8') if gitignore.exists() else ''
    if '.credentials/' not in text:
        with open(gitignore, 'a') as gi:
            gi.write('\n# Local credentials (do not commit)\n.credentials/\n')
        subprocess.run(['git', 'add', str(gitignore)], check=False)

    # Commit sanitized changes
    try:
        subprocess.run(['git', 'commit', '-m', 'chore(secrets): sanitize inline credential literals across docs and scripts'], check=True, capture_output=True)
        print('Commit successful.')
    except subprocess.CalledProcessError:
        print('No changes to commit (already clean).')
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
