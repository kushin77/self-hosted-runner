#!/usr/bin/env python3
"""
Add a top-level `permissions:` block to workflows that lack any top-level
`permissions:`. This is conservative: it checks the first 40 lines for an
existing `permissions:` and inserts a minimal policy after `name:` if absent.

Usage: python3 .github/scripts/add_top_level_permissions.py
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


def has_top_level_permissions(lines):
    # Return True if 'permissions:' appears within first 40 lines
    for l in lines[:40]:
        if l.strip().startswith('permissions:'):
            return True
    return False


def insert_after_name(lines):
    for i, l in enumerate(lines[:20]):
        if l.strip().startswith('name:'):
            insert_at = i + 1
            before = '\n'.join(lines[:insert_at])
            after = '\n'.join(lines[insert_at:])
            new_text = before + ('\n' if before and not before.endswith('\n') else '') + PERMISSIONS_BLOCK + ('\n' if not PERMISSIONS_BLOCK.endswith('\n') else '') + after
            return new_text
    # No name found — insert at top
    new_text = PERMISSIONS_BLOCK + '\n' + '\n'.join(lines)
    return new_text


def process_file(path: pathlib.Path) -> bool:
    text = path.read_text(encoding='utf-8')
    lines = text.splitlines()
    if has_top_level_permissions(lines):
        return False
    # Insert permissions
    new_text = insert_after_name(lines)
    path.write_text(new_text, encoding='utf-8')
    return True


def main() -> int:
    if not WORKFLOWS_DIR.exists():
        print('.github/workflows not found; nothing to do')
        return 0

    modified = []
    for p in sorted(WORKFLOWS_DIR.rglob('*.yml')) + sorted(WORKFLOWS_DIR.rglob('*.yaml')):
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
