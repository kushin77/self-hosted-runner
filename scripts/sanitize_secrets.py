#!/usr/bin/env python3
import re
from pathlib import Path
import subprocess

patterns = [
    (re.compile(r"export\s+REDACTED_AWS_SECRET_ACCESS_KEY\s*=\s*['\"]?[^\n'\"]*", re.I), 'export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY'),
    (re.compile(r"REDACTED_AWS_SECRET_ACCESS_KEY\s*:\s*[^\n]*", re.I), 'REDACTED_AWS_SECRET_ACCESS_KEY: REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY
    (re.compile(r"AWS_ACCESS_KEY_ID\s*=\s*['\"]?[^\n'\"]*", re.I), 'AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID'),
    (re.compile(r"AKIA[0-9A-Z]{16}"), 'REDACTED_AWS_ACCESS_KEY_ID'),
    (re.compile(r"REDACTED_AWS_ACCESS_KEY_ID[0-9A-Z]*"), 'REDACTED_AWS_ACCESS_KEY_ID'),
    (re.compile(r"REDACTED_AWS_SECRET_ACCESS_KEY", re.I), 'REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY'),
    (re.compile(r"REDACTED_VAULT_TOKEN", re.I), 'REDACTED_REDACTED_VAULT_TOKEN'),
]

exclude_dirs = ['.git', 'frontend/node_modules', '.vscode']
root = Path('.').resolve()

def is_excluded(p: Path):
    for d in exclude_dirs:
        if str(p).startswith(str(root.joinpath(d))):
            return True
    return False

files = []
for p in root.rglob('*'):
    if p.is_file() and not is_excluded(p):
        try:
            text = p.read_text(encoding='utf-8')
        except Exception:
            continue
        for pat, _ in patterns:
            if pat.search(text):
                files.append(p)
                break

if not files:
    print('No candidate files found.')
    raise SystemExit(0)

print('Files to patch:')
for f in files:
    print(f)

for f in files:
    s = f.read_text(encoding='utf-8')
    orig = s
    for pat, repl in patterns:
        s = pat.sub(repl, s)
    if s != orig:
        f.write_text(s, encoding='utf-8')
        subprocess.run(['git','add',str(f)])

# remove .credentials if present
cred = root.joinpath('.credentials','gcp-project-id.key')
if cred.exists():
    subprocess.run(['git','rm','-f','--ignore-unmatch', str(cred)])
    gitignore = root.joinpath('.gitignore')
    text = gitignore.read_text(encoding='utf-8') if gitignore.exists() else ''
    if '.credentials/' not in text:
        with open(gitignore,'a') as gi:
            gi.write('\n# Local credentials (do not commit)\n.credentials/\n')
        subprocess.run(['git','add','.gitignore'])

# commit if staged
staged = subprocess.run(['git','diff','--cached','--name-only'], capture_output=True, text=True)
if staged.stdout.strip():
    subprocess.run(['git','commit','-m','chore(secrets): redact inline credential literals across docs and scripts'])
    subprocess.run(['git','push','origin','main'])
    print('Committed and pushed changes')
else:
    print('No staged changes to commit')
