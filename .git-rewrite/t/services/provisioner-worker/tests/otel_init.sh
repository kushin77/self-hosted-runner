#!/usr/bin/env bash
# simple sanity check that OTEL module can initialize without crashing
set -euo pipefail

node - <<'EOF'
try {
  const otel = require('../lib/otel.cjs');
  process.env.ENABLE_OTEL='true';
  otel.init();
  console.log('otel init succeeded');
} catch (e) {
  console.error('otel init failed', e.message);
  process.exit(1);
}
EOF

echo 'otel init script ran successfully.'
