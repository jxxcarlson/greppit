#!/usr/bin/env python3
"""Tiny static dev server for greppit frontend. Reads PORT from env (default 8011)."""
import http.server
import socketserver
import os

PORT = int(os.environ.get("PORT", 8011))
os.chdir(os.path.dirname(os.path.abspath(__file__)))

Handler = http.server.SimpleHTTPRequestHandler
Handler.extensions_map['.js'] = 'application/javascript'

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"greppit frontend serving at http://localhost:{PORT}")
    httpd.serve_forever()
