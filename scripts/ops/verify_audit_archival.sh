#!/usr/bin/env bash
set -euo pipefail
# Verify chain integrity across rotated audit files (local directory)
DIR=${1:-/opt/nexusshield/scripts/cloudrun/logs/rotated}
if [ ! -d "$DIR" ]; then
  echo "Directory $DIR not found" >&2
  exit 1
fi

python3 - <<'PY'
import os,sys,json,hashlib
paths=sorted([os.path.join(sys.argv[1],p) for p in os.listdir(sys.argv[1]) if p.endswith('.jsonl.gz')])
prev_hash=None
for p in paths:
    import gzip
    with gzip.open(p,'rt',encoding='utf-8') as f:
        for line in f:
            obj=json.loads(line)
            h=obj.get('hash')
            pr=obj.get('prev')
            if prev_hash and pr!=prev_hash:
                print('CHAIN_BROKEN in',p)
                sys.exit(2)
            prev_hash=h
print('CHAIN_OK')
PY
EOF
