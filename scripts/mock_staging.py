#!/usr/bin/env python3
"""
Lightweight mock staging server for /api/v1/migrate to support local tests.
Writes simple chained audit entries to scripts/cloudrun/logs/portal-migrate-audit.jsonl
"""
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, uuid, os, time

AUDIT_PATH = os.path.join(os.path.dirname(__file__), 'cloudrun', 'logs', 'portal-migrate-audit.jsonl')
os.makedirs(os.path.dirname(AUDIT_PATH), exist_ok=True)

def append_audit(entry):
    prev = ""
    if os.path.exists(AUDIT_PATH):
        with open(AUDIT_PATH, 'rb') as f:
            try:
                last = f.readlines()[-1].decode('utf-8')
                prev = json.loads(last).get('hash','')
            except Exception:
                prev = ""
    entry['prev'] = prev
    entry['hash'] = 'h'+str(int(time.time()))
    with open(AUDIT_PATH, 'a', encoding='utf-8') as f:
        f.write(json.dumps(entry, ensure_ascii=False) + '\n')

class Handler(BaseHTTPRequestHandler):
    def _set_headers(self, code=200):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()

    def do_POST(self):
        if self.path == '/api/v1/migrate':
            length = int(self.headers.get('content-length', 0))
            body = self.rfile.read(length).decode('utf-8') if length else '{}'
            jid = str(uuid.uuid4())
            append_audit({'job_id': jid, 'event': 'job_queued'})
            resp = {'job_id': jid, 'status': 'dry-run-completed'}
            self._set_headers(200)
            self.wfile.write(json.dumps(resp).encode('utf-8'))
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({'error':'not found'}).encode('utf-8'))

    def log_message(self, format, *args):
        return

def run(port=8080):
    server = HTTPServer(('0.0.0.0', port), Handler)
    print(f"Mock staging server running on :{port}")
    server.serve_forever()

if __name__ == '__main__':
    run()
