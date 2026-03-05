#!/usr/bin/env bash
# sanity check that vault-shim OTEL module loads without error
set -euo pipefail

node - <<'EOF'
try {
  const otel = require('../lib/otel.cjs');
  process.env.ENABLE_OTEL='true';
  otel.init();
  console.log('vault-shim otel init succeeded');
} catch (e) {
  console.error('vault-shim otel init failed', e.message);
  process.exit(1);
}
EOF

echo 'vault-shim OTEL test completed.'
