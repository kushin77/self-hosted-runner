#!/usr/bin/env python3
"""Simple Prometheus metrics exporter for milestone organizer.

Exposes /metrics with:
- milestone_assignments_total{milestone="..."} count
- milestone_assignments_last_run_timestamp seconds since epoch

Reads the latest audit JSONL at artifacts/milestones-assignments/last_assignment_patch.jsonl
and the audit log file artifacts/milestones-assignments/assignments_*.jsonl
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
import os, time, glob, json

ARTIFACT_DIR = os.environ.get('ARTIFACT_DIR', 'artifacts/milestones-assignments')
PORT = int(os.environ.get('METRICS_PORT', '9112'))


def load_latest_audit():
    files = sorted(glob.glob(os.path.join(ARTIFACT_DIR, 'assignments_*.jsonl')))
    if not files:
        return {}
    latest = files[-1]
    counts = {}
    ts = 0
    with open(latest) as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            m = rec.get('milestone') or 'none'
            counts[m] = counts.get(m, 0) + 1
            ts = max(ts, int(time.time()))
    return {'counts': counts, 'timestamp': ts}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/metrics':
            self.send_response(404); self.end_headers(); return
        data = load_latest_audit()
        lines = []
        for m, c in data.get('counts', {}).items():
            name = m.replace('"', '\\"')
            lines.append(f'milestone_assignments_total{{milestone="{name}"}} {c}')
        lines.append(f'milestone_assignments_last_run_timestamp {data.get("timestamp", 0)}')
        body = '\n'.join(lines) + '\n'
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain; version=0.0.4')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body.encode())


def run():
    httpd = HTTPServer(('0.0.0.0', PORT), Handler)
    print('Metrics server listening on', PORT)
    httpd.serve_forever()


if __name__ == '__main__':
    run()
