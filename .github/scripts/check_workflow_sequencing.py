#!/usr/bin/env python3
import sys
from pathlib import Path

WORKFLOWS_DIR = Path('.github/workflows')
EXEMPT = {
    'preflight.yml',
    'secrets-scan.yml',
    'ts-check.yml',
    'validate-node-lock.yml',
    'validate-manifests.yml',
    'auto-close-on-deploy-success.yml',
    'terraform-plan-ami.yml',
}

KEYWORDS = ['workflow_run', 'workflow_call', 'needs:', 'concurrency:', 'on: workflow_run']

def main():
    if not WORKFLOWS_DIR.exists():
        print('No workflows directory found; nothing to audit.')
        return 0

    failures = []
    for p in sorted(WORKFLOWS_DIR.glob('*.yml')):
        name = p.name
        text = p.read_text(encoding='utf-8')
        if name in EXEMPT:
            print(f'OK (exempt): {name}')
            continue

        if not any(k in text for k in KEYWORDS):
            failures.append(name)
            print(f'MISSING SEQUENCING: {name}')
        else:
            print(f'OK: {name}')

    report = 'workflow-audit-report.txt'
    Path(report).write_text('\n'.join(failures) or 'All workflows passed audit', encoding='utf-8')
    print('\nReport written to', report)

    if failures:
        print(f'Found {len(failures)} workflows missing sequencing protections.')
        return 2
    return 0

if __name__ == '__main__':
    sys.exit(main())
