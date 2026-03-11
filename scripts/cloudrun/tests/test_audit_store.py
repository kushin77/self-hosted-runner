#!/usr/bin/env python3
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import audit_store


def main():
    tmp = tempfile.mktemp(suffix='.jsonl')
    try:
        # append two entries
        audit_store.append_entry(tmp, {'msg': 'one'})
        audit_store.append_entry(tmp, {'msg': 'two'})
        ok, errors = audit_store.verify_chain(tmp)
        if not ok:
            print('verify failed unexpectedly', errors)
            sys.exit(2)

        # corrupt the file by appending an invalid line and expect verification to fail
        with open(tmp, 'a', encoding='utf-8') as f:
            f.write('THIS IS INVALID JSON LINE\n')
        ok2, errors2 = audit_store.verify_chain(tmp)
        if ok2:
            print('corruption not detected')
            sys.exit(2)

        print('test_audit_store: OK')
    finally:
        try:
            os.remove(tmp)
        except Exception:
            pass


if __name__ == '__main__':
    main()
