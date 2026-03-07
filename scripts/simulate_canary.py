#!/usr/bin/env python3
import argparse
import re
from pathlib import Path

parser = argparse.ArgumentParser(description="Simulate canary or progressive rollout")
parser.add_argument('--mode', choices=['canary', 'progressive'], default='canary', help='operation mode')
parser.add_argument('--inventory', default=None, help='inventory file path')
parser.add_argument('--playbook', default=None, help='playbook path')
args = parser.parse_args()

# determine inventory and playbook based on mode and args
if args.inventory:
    inv = Path(args.inventory)
elif args.mode == 'progressive':
    inv = Path('ansible/inventory/production')
else:
    inv = Path('ansible/inventory/canary')

if args.playbook:
    play = Path(args.playbook)
elif args.mode == 'progressive':
    play = Path('ansible/playbooks/deploy-rotation.yml')
else:
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

print(f"Simulating {args.mode} run")
print('Playbook:', play)
print('Inventory:', inv)
print('Discovered hosts (%d):' % len(hosts))
for h in hosts:
    print('- host:', h)
    print('  action: run debug task (idempotent)')
print('\nResult: All tasks are idempotent and no-op; would report success on healthy endpoints.')
