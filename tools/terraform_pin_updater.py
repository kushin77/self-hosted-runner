#!/usr/bin/env python3
"""
Simple Terraform image pin updater.

Usage examples:
  # update a single image mapping
  python3 tools/terraform_pin_updater.py --path terraform/ --map '{"gcr.io/myproj/app:1.2.3":"gcr.io/myproj/app:1.2.4"}' --commit "Update image pins"

  # use a JSON file with mappings
  python3 tools/terraform_pin_updater.py --path terraform/ --map-file mappings.json

Behavior:
 - Scans files under --path for occurrences of image = "..." or image: "..." and replaces matches using mapping.
 - Keeps changes idempotent: only writes if content changes.
 - Optionally commits changes locally (no push) when --commit is provided.

Notes: Designed for direct-development workflow (commit to main locally). No PRs or GitHub Actions.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

IMAGE_RE = re.compile(r'(?P<prefix>image\s*=\s*")(?P<img>[^"\n]+)(?P<suffix>")')


def find_tf_files(path: Path):
    for p in path.rglob('*.tf'):
        yield p


def load_mappings(map_arg: str, map_file: Path):
    if map_file:
        with open(map_file, 'r') as f:
            return json.load(f)
    if map_arg:
        return json.loads(map_arg)
    return {}


def replace_in_text(text: str, mappings: dict):
    changed = False

    def repl(m):
        nonlocal changed
        img = m.group('img')
        if img in mappings:
            changed = True
            return f'{m.group("prefix")}{mappings[img]}{m.group("suffix")}'
        return m.group(0)

    out = IMAGE_RE.sub(repl, text)
    return out, changed


def stage_and_commit(files, message: str):
    if not files:
        return None
    subprocess.check_call(['git', 'add'] + [str(f) for f in files])
    subprocess.check_call(['git', 'commit', '-m', message])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--path', default='.', help='Root path to scan')
    parser.add_argument('--map', help='JSON string map of old->new image')
    parser.add_argument('--map-file', type=Path, help='Path to JSON file with mappings')
    parser.add_argument('--commit', help='Commit message to commit changes locally')
    parser.add_argument('--dry-run', action='store_true', help='Show changes without writing')
    args = parser.parse_args()

    root = Path(args.path)
    if not root.exists():
        print('Path does not exist:', root, file=sys.stderr)
        sys.exit(2)

    mappings = load_mappings(args.map, args.map_file)
    if not mappings:
        print('No mappings provided; exiting.', file=sys.stderr)
        sys.exit(3)

    changed_files = []
    for tf in find_tf_files(root):
        text = tf.read_text(encoding='utf-8')
        new_text, changed = replace_in_text(text, mappings)
        if changed:
            print(f'Updating {tf}')
            changed_files.append(tf)
            if not args.dry_run:
                tf.write_text(new_text, encoding='utf-8')

    if args.commit and changed_files:
        stage_and_commit(changed_files, args.commit)

    print('Done. Files changed:', len(changed_files))


if __name__ == '__main__':
    main()
