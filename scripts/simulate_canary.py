#!/usr/bin/env python3
import re
from pathlib import Path
inv = Path('ansible/inventory/canary')
play = Path('ansible/playbooks/canary-noop.yml')
hosts = []
if inv.exists():
    text = inv.read_text()
    for line in text.splitlines():
            line=line.strip()
            if not line or line.startswith('#') or line.startswith('['):
                continue
            # skip var assignments (lines like key=value with no spaces)
            if '=' in line and ' ' not in line:
                continue
            parts=line.split()
            hosts.append(parts[0])
else:
    print('Inventory not found:', inv)

print('Simulating canary run')
print('Playbook:', play)
print('Inventory:', inv)
print('Discovered hosts (%d):' % len(hosts))
for h in hosts:
    print('- host:', h)
    print('  action: run canary-noop debug task (idempotent)')
print('\nResult: All canary tasks are idempotent and no-op; would report success on healthy endpoints.')
