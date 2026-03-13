#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(body).encode())

    def do_GET(self):
        if self.path.startswith('/v1/sys/health'):
            self._send(200, {"initialized": True, "sealed": False})
            return
        if self.path.startswith('/v1/auth/approle/role/example-role/secret-id'):
            self._send(200, {"data": {"secret_id": "mock-secret-id-123456"}})
            return
        self._send(404, {"error": "not found"})

    def do_POST(self):
        self.do_GET()

if __name__ == '__main__':
    port = 8200
    server = HTTPServer(('127.0.0.1', port), Handler)
    print(f"Mock Vault server running on http://127.0.0.1:{port}")
    server.serve_forever()
