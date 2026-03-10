#!/usr/bin/env bash
# Verify air-gap networking: default OUTPUT policy should be DROP and only
# whitelist domains allowed. This is a heuristic check for compliance.
set -euo pipefail

POLICY=$(iptables -L OUTPUT -n | grep '^Chain OUTPUT')
echo "OUTPUT policy line: $POLICY"

# check default policy
if echo "$POLICY" | grep -q 'policy DROP'; then
  echo "Default OUTPUT policy is DROP (good)"
else
  echo "WARNING: default OUTPUT policy is not DROP" >&2
fi

echo "Allowed egress rules:"
iptables -L OUTPUT -n --line-numbers | grep -E 'github.com|amazonaws|cloud\.google' || true

echo "Manual verification of whitelist required."
