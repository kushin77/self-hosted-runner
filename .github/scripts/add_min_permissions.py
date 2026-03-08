#!/usr/bin/env python3
"""
Insert a minimal `permissions:` block into GitHub workflow YAML files that
do not already declare `permissions:`. This is a safe, idempotent edit: files
that already include `permissions:` are left unchanged.

Usage: python3 .github/scripts/add_min_permissions.py
"""
import pathlib
import sys

WORKFLOWS_DIR = pathlib.Path('.github/workflows')

PERMISSIONS_BLOCK = (
    'permissions:\n'
    '  contents: read\n'
    '  id-token: write\n'
    '  actions: read\n'
)


def process_file(path: pathlib.Path) -> bool:
    text = path.read_text(encoding='utf-8')
    if 'permissions:' in text:
        return False

    lines = text.splitlines()
    insert_at = 0

    # Try to insert after `name:` if present, otherwise before `on:` if present,
    # otherwise at the top of the file.
    for i, line in enumerate(lines[:6]):
        if line.strip().startswith('name:'):
            insert_at = i + 1
            break
        if line.strip().startswith('on:'):
            insert_at = i
            break

    # Build new content with the permissions block inserted.
    before = '\n'.join(lines[:insert_at])
    after = '\n'.join(lines[insert_at:])
    new_text = before + ('\n' if before and not before.endswith('\n') else '') + PERMISSIONS_BLOCK + ('\n' if not PERMISSIONS_BLOCK.endswith('\n') else '') + after
    path.write_text(new_text, encoding='utf-8')
    return True


def main() -> int:
    if not WORKFLOWS_DIR.exists():
        print('.github/workflows not found; nothing to do')
        return 0

    modified = []
    for p in sorted(WORKFLOWS_DIR.glob('*.yml')) + sorted(WORKFLOWS_DIR.glob('*.yaml')):
        try:
            changed = process_file(p)
            if changed:
                modified.append(str(p))
                print('UPDATED', p)
        except Exception as e:
            print('ERROR', p, e, file=sys.stderr)

    print(f'Total workflows updated: {len(modified)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
