#!/usr/bin/env python3
"""Shader test server. Run from the shaders/ directory."""
import http.server, json, os, sys, subprocess, threading

PORT = 8080
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Find all shader folders (contain package.json with junctionrelay key)
shaders = []
for name in sorted(os.listdir(".")):
    pkg = os.path.join(name, "package.json")
    if os.path.isfile(pkg):
        try:
            with open(pkg) as f:
                data = json.load(f)
            jr = data.get("junctionrelay", {})
            label = jr.get("displayName", name)
            emoji = jr.get("emoji", "")
            shaders.append((name, f"{emoji} {label}".strip()))
        except Exception:
            pass

url = f"http://localhost:{PORT}/test.html"
first = f"{url}?path={shaders[0][0]}" if shaders else url

def open_browser():
    try:
        if sys.platform == "win32":
            os.startfile(first)
        elif sys.platform == "darwin":
            subprocess.Popen(["open", first])
        else:
            subprocess.Popen(["xdg-open", first])
    except Exception:
        pass

server = http.server.HTTPServer(("", PORT), http.server.SimpleHTTPRequestHandler)
threading.Timer(0.5, open_browser).start()

print(f"\n  Shader test server running at:\n")
for name, label in shaders:
    print(f"  {label:<30}  {url}?path={name}")
print(f"\n  Press Ctrl+C to stop.\n")

server.serve_forever()
