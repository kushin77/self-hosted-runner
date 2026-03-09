#!/bin/bash
# System Health Dashboard
set -euo pipefail

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                   SYSTEM HEALTH DASHBOARD                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Component health status
echo "🔧 Component Status:"
[ -d ".deployment-audit" ] && echo "  ✓ Deployment audit logs" || echo "  ✗ Deployment audit logs"
[ -d ".operations-audit" ] && echo "  ✓ Operations audit logs" || echo "  ✗ Operations audit logs"
[ -d ".monitoring-hub" ] && echo "  ✓ Monitoring system" || echo "  ✗ Monitoring system"

# Scripts availability
SCRIPT_COUNT=$(find scripts -type f -executable 2>/dev/null | wc -l)
echo ""
echo "📝 Available Scripts: $SCRIPT_COUNT"

# Workflow status
WF_COUNT=$(ls .github/workflows/*.yml 2>/dev/null | wc -l)
echo "🔄 Active Workflows: $WF_COUNT"

# Audit trail size
AUDIT_SIZE=$(du -sh .{deployment,operations,monitoring}-audit 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0B")
echo "📋 Audit Trail Size: $AUDIT_SIZE"

# Recent activity
echo ""
echo "📅 Recent Activity (Last 24h):"
RECENT=$(find . -name "*.jsonl" -mtime -1 2>/dev/null | wc -l)
echo "  Audit events logged: $RECENT"

echo ""
