#!/usr/bin/env python3
"""Verify append-only audit chain integrity"""
import sys
from scripts.cloudrun import audit_store as _audit if __package__ else __import__('audit_store') as _audit

def main(path):
    ok, errors = _audit.verify_chain(path)
    if ok:
        print('OK: audit chain valid')
        return 0
    else:
        print('ERROR: audit chain invalid')
        for e in errors:
            print(e)
        return 2

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('usage: audit_verify.py path/to/audit.jsonl')
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
