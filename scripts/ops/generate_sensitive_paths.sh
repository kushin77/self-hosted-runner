#!/usr/bin/env bash
set -euo pipefail

# Generates a newline-separated list of unique repo paths that appeared in
# reports/secret-scan-report-redacted.json. Output is written to the file
# provided as first argument (defaults to reports/sensitive-paths.txt).

OUT=${1:-reports/sensitive-paths.txt}
SRC=reports/secret-scan-report-redacted.json

if [ ! -f "$SRC" ]; then
  echo "Error: $SRC not found" >&2
  exit 2
fi

python3 - <<'PY' > "$OUT"
import json
data=json.load(open('reports/secret-scan-report-redacted.json'))
paths=set()
for e in data:
    f=e.get('file') or e.get('File') or e.get('path')
    if not f:
        continue
    # normalize
    f=f.strip()
    paths.add(f)

for p in sorted(paths):
    print(p)
PY

echo "Wrote sensitive path list to $OUT"
