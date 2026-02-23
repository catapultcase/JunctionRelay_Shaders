#!/usr/bin/env python3
"""Tiny HTTP server for shader test page. Run from the shader folder."""
import http.server, os, sys, subprocess, threading

PORT = 8080
os.chdir(os.path.dirname(os.path.abspath(__file__)))

url = f"http://localhost:{PORT}/test.html"

def open_browser():
    try:
        if sys.platform == "win32":
            os.startfile(url)
        elif sys.platform == "darwin":
            subprocess.Popen(["open", url])
        else:
            subprocess.Popen(["xdg-open", url])
    except Exception:
        pass  # URL is printed below — user can click it

server = http.server.HTTPServer(("", PORT), http.server.SimpleHTTPRequestHandler)
threading.Timer(0.5, open_browser).start()

print(f"\n  Shader test server running — open in browser:\n")
print(f"  {url}\n")
print(f"  Press Ctrl+C to stop.\n")

server.serve_forever()
