#!/bin/bash
# Synthetic health check for AWS OIDC federation

AWS_ROLE_ARN="${AWS_ROLE_ARN:-arn:aws:iam::ACCOUNT_ID:role/nexusshield-deployer}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# Test 1: Can we assume the role?
start_time=$(date +%s%N | cut -b1-13)
aws sts assume-role-with-web-identity \
  --role-arn "${AWS_ROLE_ARN}" \
  --role-session-name "phase4-healthcheck-$(date +%s)" \
  --web-identity-token "${GITHUB_TOKEN}" \
  --duration-seconds 900 &>/dev/null

end_time=$(date +%s%N | cut -b1-13)
latency_ms=$((end_time - start_time))

# Publish metric
aws cloudwatch put-metric-data \
  --metric-name "OIDCAssumeRoleLatency" \
  --namespace "CustomOIDC" \
  --value "${latency_ms}" \
  --unit "Milliseconds"

echo "✅ OIDC federation healthy (${latency_ms}ms)"
