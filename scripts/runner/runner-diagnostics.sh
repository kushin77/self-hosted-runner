#!/usr/bin/env bash
set -euo pipefail

mkdir -p runner-diagnostics
echo "Collecting runner diagnostics..."
uptime > runner-diagnostics/uptime.txt || true
hostnamectl > runner-diagnostics/host.txt || true
df -h > runner-diagnostics/disk.txt || true
free -m > runner-diagnostics/mem.txt || true
ps aux --sort=-%mem | head -n 50 > runner-diagnostics/top-procs.txt || true
echo "Diagnostics written to runner-diagnostics/"
