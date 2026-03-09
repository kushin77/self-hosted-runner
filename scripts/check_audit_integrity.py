#!/usr/bin/env python3
"""Simple audit integrity check for JSONL audit logs.

Checks that at least one JSONL log file exists under `logs/` and that its
most recent entry timestamp is within the last 24 hours. Exits non-zero
if the check fails.
"""
import sys
from pathlib import Path
from datetime import datetime, timezone, timedelta
import json


def find_log_files(root="logs"):
    p = Path(root)
    if not p.exists():
        return []
    return sorted(p.glob('*.jsonl'))


def last_entry_time(file_path):
    try:
        with open(file_path, 'rb') as f:
            # Read from end to find last non-empty line
            f.seek(0, 2)
            size = f.tell()
            chunk_size = 1024
            data = b''
            pos = size
            while pos > 0:
                read_size = min(chunk_size, pos)
                pos -= read_size
                f.seek(pos)
                chunk = f.read(read_size)
                data = chunk + data
                if b"\n" in data:
                    break
            lines = data.splitlines()
            # get last non-empty line
            for line in reversed(lines):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line.decode('utf-8')) if isinstance(line, bytes) else json.loads(line)
                    ts = obj.get('timestamp') or obj.get('time') or obj.get('ts')
                    if ts:
                        # parse ISO-like timestamps
                        try:
                            return datetime.fromisoformat(ts.replace('Z', '+00:00'))
                        except Exception:
                            # try numeric
                            try:
                                return datetime.fromtimestamp(float(ts), tz=timezone.utc)
                            except Exception:
                                continue
                except Exception:
                    continue
    except Exception:
        return None
    return None


def main():
    files = find_log_files()
    if not files:
        print("ERROR: No audit log files found under logs/", file=sys.stderr)
        sys.exit(2)

    now = datetime.now(timezone.utc)
    latest = None
    for f in files:
        t = last_entry_time(f)
        if t:
            if not latest or t > latest:
                latest = t

    if not latest:
        print("ERROR: No timestamped entries found in logs/", file=sys.stderr)
        sys.exit(2)

    age = now - latest
    if age > timedelta(hours=24):
        print(f"ERROR: Latest audit log entry is too old ({age}).", file=sys.stderr)
        sys.exit(2)

    print(f"OK: Latest audit entry at {latest.isoformat()}")
    sys.exit(0)


if __name__ == '__main__':
    main()
