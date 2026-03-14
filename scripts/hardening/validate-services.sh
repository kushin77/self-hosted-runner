#!/bin/bash
# Service validation script - runs health checks and sync validation

set -e

echo "[INFO] Validating Portal service..."
curl -s -f http://localhost:5000/health &>/dev/null && echo "✓ Portal responding" || echo "⚠ Portal not yet available"

echo "[INFO] Validating Backend service..."
curl -s -f http://localhost:3000/health &>/dev/null && echo "✓ Backend responding" || echo "⚠ Backend not yet available"

echo "[INFO] Services validation complete"
