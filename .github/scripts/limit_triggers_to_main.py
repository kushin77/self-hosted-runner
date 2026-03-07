#!/usr/bin/env python3
"""
Limit `push` and `pull_request` triggers in workflows to the `main` branch
by adding a `branches: [main]` filter where missing. This prevents workflows
from running on rollout branches while keeping other event types intact.

Idempotent: skips workflows that already specify branches for push/pull_request.
"""
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[1]
WF_DIR = ROOT / '.github' / 'workflows'


def process(path: Path) -> bool:
    text = path.read_text(encoding='utf-8')
    try:
        data = yaml.safe_load(text)
    except Exception:
        return False
    if not isinstance(data, dict) or 'on' not in data:
        return False
    changed = False
    on = data['on']
    # on can be a list or dict or string
    if isinstance(on, dict):
        for ev in ('push', 'pull_request'):
            if ev in on:
                val = on[ev]
                # if val is None or True, replace with dict
                if val is None or val is True:
                    on[ev] = {'branches': ['main']}
                    changed = True
                elif isinstance(val, dict):
                    if 'branches' not in val and 'branches-ignore' not in val:
                        val['branches'] = ['main']
                        changed = True
                # if it's a list, leave it
    else:
        # when `on` is list or string, skip
        return False

    if changed:
        path.write_text(yaml.safe_dump(data, sort_keys=False), encoding='utf-8')
    return changed


def main():
    modified = []
    for wf in sorted(WF_DIR.glob('*.yml')):
        try:
            if process(wf):
                modified.append(str(wf))
        except Exception as e:
            print('error', wf, e)
    if modified:
        print('Modified:')
        for m in modified:
            print(' -', m)
    else:
        print('No trigger changes required')


if __name__ == '__main__':
    main()
