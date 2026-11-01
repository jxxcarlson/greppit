#!/usr/bin/env python3
"""Check that the Content-Security-Policy in frontend/index.html allows its
import map. The CSP allows that one inline script by its SHA-256 hash, so
any edit to the import map needs a new hash, or CodeMirror won't load.

    python3 scripts/csp-hash.py

Prints the current hash, and exits 1 if the CSP doesn't contain it.
"""
import base64, hashlib, re, sys
from pathlib import Path

index = Path(__file__).resolve().parent.parent / "frontend" / "index.html"
html = index.read_text(encoding="utf-8")
m = re.search(r'<script type="importmap">(.*?)</script>', html, re.S)
if not m:
    sys.exit("No import map found in frontend/index.html")
h = "sha256-" + base64.b64encode(hashlib.sha256(m.group(1).encode("utf-8")).digest()).decode()
print(h)
if f"'{h}'" not in html:
    sys.exit("The Content-Security-Policy in frontend/index.html does not have this hash: "
             "replace the old 'sha256-...' in its script-src with the one above.")
print("OK: the Content-Security-Policy allows the import map.")
