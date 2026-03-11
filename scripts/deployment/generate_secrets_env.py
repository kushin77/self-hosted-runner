#!/usr/bin/env python3
"""Generate `secrets.env` from `secrets.env.template` by fetching secrets from
Vault/GSM/AWS where available. Intended to run on target host (not CI).
"""
import os
import re
from pathlib import Path

TEMPLATE = Path("secrets.env.template")
OUT = Path("secrets.env")

if not TEMPLATE.exists():
    print("secrets.env.template not found; aborting")
    raise SystemExit(1)

# Import provider
try:
    from scripts.cloudrun.secret_providers import get_secret
except Exception:
    # fallback: try module path
    import importlib.util
    spec = importlib.util.spec_from_file_location("secret_providers", "./scripts/cloudrun/secret_providers.py")
    sp = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sp)
    get_secret = sp.get_secret

kv_re = re.compile(r"^([A-Z0-9_]+)=(.*)$")
lines = TEMPLATE.read_text().splitlines()
out_lines = []
for ln in lines:
    m = kv_re.match(ln)
    if not m:
        out_lines.append(ln)
        continue
    key = m.group(1)
    # Don't write secret if template has example value
    try:
        val = get_secret(key)
    except Exception:
        val = None
    if val:
        # Escape newlines
        val = val.replace('\n', '\\n')
        out_lines.append(f"{key}={val}")
    else:
        out_lines.append(f"{key}=")

OUT.write_text("\n".join(out_lines) + "\n")
print(f"Wrote {OUT}")
