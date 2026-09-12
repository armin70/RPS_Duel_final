import json
import os
import urllib.request

base = os.environ.get("RPS_SERVER_HTTP", "http://127.0.0.1:8000").rstrip("/")
with urllib.request.urlopen(base + "/health", timeout=10) as response:
    payload = json.loads(response.read().decode("utf-8"))
print(payload)
if not payload.get("ok"):
    raise SystemExit(1)
