#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/api/v1/secrets/health', '/api/v1/secrets/health/'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status":"ok"}).encode())
        elif self.path in ('/api/v1/secrets/resolve', '/api/v1/secrets/resolve/'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"primary_provider":"gsm"}).encode())
        elif self.path.startswith('/api/v1/secrets/credentials'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"name":"test","value":"REDACTED"}).encode())
        elif self.path in ('/api/v1/secrets/migrations', '/api/v1/secrets/migrations/'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"migrations":[]} ).encode())
        elif self.path in ('/api/v1/secrets/audit', '/api/v1/secrets/audit/'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"audit":[]} ).encode())
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8000), Handler)
    print('Fallback health API listening on http://0.0.0.0:8000')
    server.serve_forever()
