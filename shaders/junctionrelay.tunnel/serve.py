#!/usr/bin/env python3
"""Tiny HTTP server for shader test page. Run from the shader folder."""
import http.server, os, webbrowser, threading

PORT = 8080
os.chdir(os.path.dirname(os.path.abspath(__file__)))

url = f"http://localhost:{PORT}/test.html"
threading.Timer(0.5, lambda: webbrowser.open(url)).start()

print(f"\n  Shader test server running at:\n")
print(f"  \033[1;36m{url}\033[0m\n")
print(f"  Press Ctrl+C to stop.\n")

http.server.HTTPServer(("", PORT), http.server.SimpleHTTPRequestHandler).serve_forever()
