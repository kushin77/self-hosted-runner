#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length)
        with open('/tmp/mock_webhook.log', 'ab') as f:
            f.write(b'PATH: ' + self.path.encode() + b"\n")
            f.write(b'HEADERS:\n')
            for k, v in self.headers.items():
                f.write(f"{k}: {v}\n".encode())
            f.write(b'BODY:\n')
            f.write(body + b"\n---\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 5001), Handler)
    server.serve_forever()
