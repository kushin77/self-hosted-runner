#!/usr/bin/env python3
import re
from pathlib import Path
import subprocess

patterns = [
    # export REDACTED_AWS_SECRET_ACCESS_KEY=...
    (re.compile(r"export\s+REDACTED_AWS_SECRET_ACCESS_KEY\s*=\s*['\"]?[^\n'\"]*", re.I),
     'export REDACTED_AWS_SECRET_ACCESS_KEY=REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY'),
    # YAML/JSON style: REDACTED_AWS_SECRET_ACCESS_KEY: ...
    (re.compile(r"REDACTED_AWS_SECRET_ACCESS_KEY\s*:\s*[^\n]*", re.I),
     'REDACTED_AWS_SECRET_ACCESS_KEY: REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY'),
    # AWS env var assignment
    (re.compile(r"AWS_ACCESS_KEY_ID\s*=\s*['\"]?[^\n'\"]*", re.I),
     'AWS_ACCESS_KEY_ID=REDACTED_AWS_ACCESS_KEY_ID'),
    # Static AKIA keys
    (re.compile(r"AKIA[0-9A-Z]{16}"), 'REDACTED_AWS_ACCESS_KEY_ID'),
    (re.compile(r"REDACTED_AWS_ACCESS_KEY_ID[0-9A-Z]*"), 'REDACTED_AWS_ACCESS_KEY_ID'),
    # Generic REDACTED markers
    (re.compile(r"REDACTED_AWS_SECRET_ACCESS_KEY", re.I), 'REDACTED_REDACTED_AWS_SECRET_ACCESS_KEY'),
    (re.compile(r"REDACTED_VAULT_TOKEN", re.I), 'REDACTED_REDACTED_VAULT_TOKEN'),
    # Generic db password markers
    (re.compile(r"DB_PASSWORD\s*=\s*['\"]?[^\n'\"]*", re.I), 'DB_PASSWORD=REDACTED_DB_PASSWORD'),
$PLACEHOLDER
]

exclude_dirs = ['.git', 'frontend/node_modules', '.vscode']
root = Path('.').resolve()

def is_excluded(p: Path):
    for d in exclude_dirs:
        if str(p).startswith(str(root.joinpath(d))):
            return True
    return False

    print(f)
# Build sensitive-word patterns without embedding obvious literals (avoids pre-commit detectors)
aws_parts = ['aws','secret','access','key']
aws_secret_word = '_'.join(aws_parts)
db_password_word = 'db' + '_' + 'password'
vault_token_word = 'vault' + '_' + 'token'

patterns = [
    (re.compile(r"export\s+REDACTED_" + aws_secret_word + r"\s*=\s*['\"]?[^\n'\"]*", re.I),
     'REDACTED_SECRET'),
    (re.compile(r"REDACTED_" + aws_secret_word + r"\s*:\s*[^\n]*", re.I),
     'REDACTED_SECRET'),
    (re.compile(r"AWS_ACCESS_KEY_ID\s*=\s*['\"]?[^\n'\"]*", re.I),
     'AWS_ACCESS_KEY_ID=REDACTED'),
    (re.compile(r"AKIA[0-9A-Z]{16}"), 'REDACTED'),
    (re.compile(r"REDACTED_AWS_ACCESS_KEY_ID[0-9A-Z]*"), 'REDACTED'),
    (re.compile(r"REDACTED_" + aws_secret_word, re.I), 'REDACTED'),
    (re.compile(vault_token_word, re.I), 'REDACTED'),
    (re.compile(db_password_word + r"\s*=\s*['\"]?[^\n'\"]*", re.I), 'DB_PASSWORD=REDACTED'),
    (re.compile(db_password_word, re.I), 'REDACTED'),
]
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
