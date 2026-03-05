#!/usr/bin/env bash
# verify audit entries are written when jobs processed
set -euo pipefail

# use node to log a dummy event using the audit module
node - <<'EOFJS'
const audit = require('../lib/audit.cjs');
audit.log({event:'test_event', detail:'audit_test'});
console.log('node audit.log invoked');
EOFJS

# check for audit file entry
FILE=${AUDIT_FILE:-/var/log/rc-audit.log}
if grep -q 'test_event' "$FILE"; then
  echo "audit entry found in $FILE"
else
  echo "audit entry NOT found, check $FILE" >&2
  exit 1
fi

echo "audit_test script completed." 
