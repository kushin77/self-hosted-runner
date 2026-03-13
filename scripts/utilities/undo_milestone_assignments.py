#!/usr/bin/env python3
"""Undo milestone assignments from a patch file.

Usage: python3 undo_milestone_assignments.py --patch artifacts/milestones-assignments/last_assignment_patch.jsonl --confirm

Requires GH auth and will attempt to set each issue's milestone back to the
`old_milestone` (or remove milestone if null).
"""
import argparse
import json
import subprocess


def revert_issue(number, old):
    if old in (None, '', 'null'):
        cmd = ['gh', 'issue', 'edit', str(number), '--milestone', 'none']
    else:
        cmd = ['gh', 'issue', 'edit', str(number), '--milestone', old]
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode == 0, p.stderr.strip()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--patch', required=True)
    p.add_argument('--confirm', action='store_true')
    args = p.parse_args()

    if not args.confirm:
        print('Refusing to run without --confirm')
        raise SystemExit(2)

    failures = []
    successes = 0
    with open(args.patch) as f:
        for line in f:
            rec = json.loads(line)
            num = rec['number']
            old = rec.get('old_milestone')
            ok, err = revert_issue(num, old)
            if ok:
                successes += 1
            else:
                failures.append({'issue': num, 'err': err})

    print('Reverted', successes, 'failed', len(failures))
    if failures:
        print('Sample failures:', failures[:10])
        raise SystemExit(3)


if __name__ == '__main__':
    main()
