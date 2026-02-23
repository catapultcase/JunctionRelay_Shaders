#!/usr/bin/env python3
"""Shader test server. Run from the repo root."""
import http.server, json, os, sys, subprocess, threading

PORT = 8080
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# Find all shader folders under shaders/
shaders = []
shaders_dir = "shaders"
if os.path.isdir(shaders_dir):
    for name in sorted(os.listdir(shaders_dir)):
        pkg = os.path.join(shaders_dir, name, "package.json")
        if os.path.isfile(pkg):
            try:
                with open(pkg, encoding="utf-8") as f:
                    data = json.load(f)
                jr = data.get("junctionrelay", {})
                label = jr.get("displayName", name)
                shaders.append((name, label))
            except Exception:
                pass

if not shaders:
    print("  No shaders found in shaders/ directory.")
    sys.exit(1)

url = f"http://localhost:{PORT}/test.html"

# Show numbered list and let user pick
print(f"\n  Available shaders:\n")
for i, (name, label) in enumerate(shaders, 1):
    print(f"    {i:>2}.  {label}")

print()
choice = input(f"  Select shader [1-{len(shaders)}]: ").strip()
try:
    idx = int(choice) - 1
    if idx < 0 or idx >= len(shaders):
        raise ValueError
except ValueError:
    print(f"  Invalid selection.")
    sys.exit(1)

selected_name, selected_label = shaders[idx]
target = f"{url}?path={selected_name}"

def open_browser():
    try:
        if sys.platform == "win32":
            os.startfile(target)
        elif sys.platform == "darwin":
            subprocess.Popen(["open", target])
        else:
            subprocess.Popen(["xdg-open", target])
    except Exception:
        pass

server = http.server.HTTPServer(("", PORT), http.server.SimpleHTTPRequestHandler)
threading.Timer(0.5, open_browser).start()

print(f"\n  Serving: {selected_label}")
print(f"  {target}\n")
print(f"  Press Ctrl+C to stop.\n")

server.serve_forever()
