#!/usr/bin/env python3
# ⚡ COMPATIBILITY SHIM (EPIC-4)
import logging
import subprocess
import sys

logging.warning(
    "[BACKWARD COMPAT] Redirecting scripts/pmo/intelligence_runner.py -> scripts/pmo/autonomous_executive_agents.py --compat intelligence_runner.py"
)
cmd = [
    "python3",
    "scripts/pmo/autonomous_executive_agents.py --compat intelligence_runner.py",
] + sys.argv[1:]
subprocess.run(cmd)
