#!/usr/bin/env python3
"""
Minimal interactive reclassification report scaffold.
Reads classification JSON and emits a simple HTML file listing groups and top issues.
"""
import json
import sys

if len(sys.argv) < 3:
    print('Usage: report_generator.py <classification.json> <out.html>')
    sys.exit(1)

with open(sys.argv[1]) as f:
    data = json.load(f)

out = ['<html><head><meta charset="utf-8"><title>Milestone Organizer Report</title></head><body>']
out.append('<h1>Milestone Organizer - Classification Report</h1>')
for k, v in data.items():
    out.append(f'<h2>{k} ({len(v)})</h2>')
    out.append('<ul>')
    for item in v[:50]:
        out.append(f"<li>#{item['number']} (score: {item.get('score')})</li>")
    out.append('</ul>')
out.append('</body></html>')
with open(sys.argv[2], 'w') as f:
    f.write('\n'.join(out))
print('Wrote report to', sys.argv[2])
