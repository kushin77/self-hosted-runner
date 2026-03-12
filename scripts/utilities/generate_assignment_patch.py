#!/usr/bin/env python3
"""Generate an assignment patch file from pre/post issue snapshots.

Usage: generate_assignment_patch.py --pre pre.json --post post.json --out patch.jsonl

Writes one JSON object per line: {number, old_milestone, new_milestone, timestamp}
"""
import argparse, json, time, sys


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--pre', required=True)
    p.add_argument('--post', required=True)
    p.add_argument('--out', required=True)
    args = p.parse_args()

    try:
        pre_list = json.load(open(args.pre))
    except Exception:
        pre_list = []
    try:
        post_list = json.load(open(args.post))
    except Exception:
        post_list = []

    pre_map = {i['number']:(i.get('milestone') or {}).get('title') for i in pre_list}
    post_map = {i['number']:(i.get('milestone') or {}).get('title') for i in post_list}

    ts = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    changed = 0
    with open(args.out, 'w') as outf:
        for num, new in post_map.items():
            old = pre_map.get(num)
            if old != new:
                rec = {'number': num, 'old_milestone': old, 'new_milestone': new, 'timestamp': ts}
                outf.write(json.dumps(rec) + '\n')
                changed += 1

    # Ensure file exists even if empty
    print('WROTE', args.out, 'entries:', changed)
    return 0


if __name__ == '__main__':
    sys.exit(main())
#!/usr/bin/env python3
"""Generate an assignment patch file from pre/post snapshots.

Usage: generate_assignment_patch.py --pre open_pre.json --post open.json --out patch.jsonl

Writes one JSON object per line with keys: number, old_milestone, new_milestone, timestamp
"""
import argparse
import json
import time
import sys
from pathlib import Path


def load(path):
    p = Path(path)
    if not p.exists():
        return []
    try:
        return json.load(p)
    except Exception as e:
        print('ERROR: failed to load', path, e, file=sys.stderr)
        return []


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--pre', required=True)
    p.add_argument('--post', required=True)
    p.add_argument('--out', required=True)
    args = p.parse_args()

    pre = load(args.pre)
    post = load(args.post)
    pre_map = {i['number']:(i.get('milestone') or {}).get('title') for i in pre}
    post_map = {i['number']:(i.get('milestone') or {}).get('title') for i in post}

    recs = []
    ts = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    for num, new in post_map.items():
        old = pre_map.get(num)
        if old != new:
            recs.append({'number': num, 'old_milestone': old, 'new_milestone': new, 'timestamp': ts})

    outp = Path(args.out)
    outp.parent.mkdir(parents=True, exist_ok=True)
    with open(outp, 'w') as f:
        for r in recs:
            f.write(json.dumps(r) + '\n')

    print('WROTE', args.out, 'ENTRIES', len(recs))


if __name__ == '__main__':
    main()
