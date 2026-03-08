#!/bin/bash
# setup_aws_kms.sh - Setup AWS KMS and OIDC provider
# Stub implementation for local development

set -euo pipefail

echo "Setting up AWS KMS..."

# Check if AWS credentials are available
if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
    echo "⚠️  WARNING: AWS_ACCOUNT_ID not set"
    echo "    Skipping AWS KMS setup - assuming local development"
    exit 0
fi

# Verify aws CLI is installed
if ! command -v aws &> /dev/null; then
    echo "⚠️  WARNING: aws CLI not found"
    echo "    Skipping AWS KMS setup"
    exit 0
fi

echo "✅ AWS KMS setup validation complete (stub mode)"
exit 0
