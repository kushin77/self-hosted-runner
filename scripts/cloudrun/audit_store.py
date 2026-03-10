import os
import json
import hashlib
from datetime import datetime

def _read_last_hash(path):
    if not os.path.exists(path):
        return '0' * 64
    try:
        with open(path, 'rb') as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            if size == 0:
                return '0' * 64
            # read last 8K bytes to find last newline
            to_read = min(size, 8192)
            f.seek(-to_read, os.SEEK_END)
            data = f.read().decode('utf-8', errors='ignore')
            lines = data.strip().splitlines()
            if not lines:
                return '0' * 64
            last = lines[-1]
            try:
                j = json.loads(last)
                return j.get('hash', '0' * 64)
            except Exception:
                return '0' * 64
    except Exception:
        return '0' * 64

def append_entry(path, entry: dict):
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
    entry.setdefault('ts', datetime.utcnow().isoformat() + 'Z')
    prev = _read_last_hash(path)
    # canonical JSON
    payload = json.dumps(entry, separators=(',', ':'), sort_keys=True, ensure_ascii=False)
    h = hashlib.sha256((prev + payload).encode('utf-8')).hexdigest()
    line = json.dumps({'prev': prev, 'hash': h, 'entry': entry}, ensure_ascii=False) + '\n'
    with open(path, 'a', encoding='utf-8') as f:
        f.write(line)
    return h

def verify_chain(path):
    if not os.path.exists(path):
        return True, []
    prev = '0' * 64
    errors = []
    with open(path, 'r', encoding='utf-8') as f:
        for i, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                j = json.loads(line)
                entry = j.get('entry')
                expected_hash = j.get('hash')
                payload = json.dumps(entry, separators=(',', ':'), sort_keys=True, ensure_ascii=False)
                actual = hashlib.sha256((prev + payload).encode('utf-8')).hexdigest()
                if actual != expected_hash:
                    errors.append({'line': i, 'expected': expected_hash, 'actual': actual})
                    break
                prev = expected_hash
            except Exception as e:
                errors.append({'line': i, 'error': str(e)})
                break
    return (len(errors) == 0), errors
