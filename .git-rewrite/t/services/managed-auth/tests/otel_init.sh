#!/usr/bin/env bash
# sanity check that managed-auth OTEL module loads without error
set -euo pipefail

node - <<'EOF'
try {
  const otel = require('../lib/otel.cjs');
  process.env.ENABLE_OTEL='true';
  otel.init();
  console.log('managed-auth otel init succeeded');
} catch (e) {
  console.error('managed-auth otel init failed', e.message);
  process.exit(1);
}
EOF

echo 'managed-auth OTEL test completed.'
