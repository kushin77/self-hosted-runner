#!/bin/bash
# Comprehensive Deployment Automation System (moved to scripts/)
# See: /home/akushnir/self-hosted-runner/deploy-production-final.sh for full implementation

readonly TARGET="192.168.168.42"
readonly NAS="192.168.168.39"

echo "🚀 Comprehensive Deployment System"
echo "Target: $TARGET"
echo "NAS: $NAS"
echo ""
echo "⚠️  This system is automated via:"
echo "  - Main executor: deploy-production-final.sh"
echo "  - Continuous sync: continuous-deployment.sh"
echo "  - GitHub tracking: github-issue-automation.sh"
echo ""
echo "✅ Execute: bash deploy-production-final.sh"
