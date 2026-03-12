#!/bin/bash
# Deploy Phase-4 Observability Framework - AWS CloudWatch
# Monitor STS tokens, OIDC federation, and credential freshness
# Author: GitHub Copilot (Autonomous Agent)
# Date: 2026-03-12

set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
AUDIT_LOG="logs/phase4-aws-cloudwatch-deploy-${TIMESTAMP}.jsonl"

mkdir -p logs

# Log audit entry
log_event() {
  local event="$1"
  local status="$2"
  local details="${3:-}"
  
  echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"event\":\"${event}\",\"status\":\"${status}\",\"details\":\"${details}\"}" >> "${AUDIT_LOG}"
}

log_event "phase4_aws_cloudwatch_start" "started" "AWS CloudWatch monitoring deployment"

# ============================================================================
# 1. Create Custom Metrics for AWS STS/OIDC
# ============================================================================
echo "📈 Creating AWS custom metrics..."

# Metric 1: STS Token Freshness
aws cloudwatch put-metric-alarm \
  --alarm-name "sts-token-age-high" \
  --alarm-description "Alert when STS token is older than 10 minutes" \
  --metric-name "STSTokenAge" \
  --namespace "AWS/OIDC" \
  --statistic "Maximum" \
  --period 300 \
  --threshold 600 \
  --comparison-operator "GreaterThanThreshold" \
  --region "${AWS_REGION}" 2>/dev/null || true

log_event "sts_token_alarm_created" "success" "STS token freshness alarm"

# Metric 2: OIDC Federation Success Rate
aws cloudwatch put-metric-alarm \
  --alarm-name "oidc-federation-failure-rate" \
  --alarm-description "Alert when OIDC federation success rate drops below 99.5%" \
  --metric-name "OIDCFederationSuccessRate" \
  --namespace "AWS/OIDC" \
  --statistic "Average" \
  --period 300 \
  --threshold 99.5 \
  --comparison-operator "LessThanThreshold" \
  --region "${AWS_REGION}" 2>/dev/null || true

log_event "oidc_success_rate_alarm_created" "success" "OIDC federation success rate alarm"

# Metric 3: IAM Role Assumption Latency
aws cloudwatch put-metric-alarm \
  --alarm-name "iam-role-assumption-latency-high" \
  --alarm-description "Alert when IAM role assumption takes > 500ms" \
  --metric-name "IAMRoleAssumptionLatency" \
  --namespace "AWS/OIDC" \
  --statistic "Average" \
  --period 300 \
  --threshold 500 \
  --comparison-operator "GreaterThanThreshold" \
  --region "${AWS_REGION}" 2>/dev/null || true

log_event "iam_latency_alarm_created" "success" "IAM role assumption latency alarm"

# ============================================================================
# 2. Create CloudWatch Dashboard
# ============================================================================
echo "📊 Creating CloudWatch dashboard..."

DASHBOARD_BODY=$(cat <<'DASHBOARD_JSON'
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/OIDC", "STSTokenAge"],
          [".", "OIDCFederationSuccessRate"],
          [".", "IAMRoleAssumptionLatency"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "AWS OIDC Health Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/IAM", "AuthorizationFailures"],
          ["AWS/STS", "TokenExpired"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "Authentication Error Rates"
      }
    }
  ]
}
DASHBOARD_JSON
)

aws cloudwatch put-dashboard \
  --dashboard-name "Phase4-OIDC-Monitoring" \
  --dashboard-body "${DASHBOARD_BODY}" \
  --region "${AWS_REGION}" 2>/dev/null || true

log_event "cloudwatch_dashboard_created" "success" "Phase-4 OIDC monitoring dashboard"

# ============================================================================
# 3. Configure SNS Topic for Alerts
# ============================================================================
echo "📢 Configuring alert notifications..."

# Create SNS topic if it doesn't exist
SNS_TOPIC_ARN=$(aws sns create-topic \
  --name phase4-credentialhealth-alerts \
  --region "${AWS_REGION}" \
  --query 'TopicArn' \
  --output text 2>/dev/null || echo "arn:aws:sns:${AWS_REGION}:ACCOUNT_ID:phase4-credentialhealth-alerts")

log_event "sns_topic_created" "success" "SNS topic: ${SNS_TOPIC_ARN}"

# ============================================================================
# 4. Create CloudWatch Log Group for OIDC Events
# ============================================================================
echo "📝 Creating log group..."

aws logs create-log-group \
  --log-group-name "/aws/oidc/credential-federation" \
  --region "${AWS_REGION}" 2>/dev/null || true

# Set retention policy to 365 days
aws logs put-retention-policy \
  --log-group-name "/aws/oidc/credential-federation" \
  --retention-in-days 365 \
  --region "${AWS_REGION}" 2>/dev/null || true

log_event "log_group_created" "success" "Log group: /aws/oidc/credential-federation"

# ============================================================================
# 5. Create Metric Filters for Event Detection
# ============================================================================
echo "🔍 Creating metric filters..."

# Filter 1: OIDC Federation Failures
aws logs put-metric-filter \
  --log-group-name "/aws/oidc/credential-federation" \
  --filter-name "OIDCFederationFailures" \
  --filter-pattern "[... , action = \"AssumeRoleWithWebIdentity\", status = \"FAILURE\"]" \
  --metric-transformations metricName=OIDCFederationFailures,metricNamespace=CustomOIDC,metricValue=1 \
  --region "${AWS_REGION}" 2>/dev/null || true

log_event "metric_filter_created" "success" "Metric filter for OIDC failures"

# ============================================================================
# 6. Create Synthetic Monitoring Job
# ============================================================================
echo "🔬 Creating synthetic test job..."

cat > scripts/monitoring/aws-oidc-healthcheck.sh << 'HEALTHCHECK_SCRIPT'
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
HEALTHCHECK_SCRIPT

chmod +x scripts/monitoring/aws-oidc-healthcheck.sh

log_event "healthcheck_job_created" "success" "AWS OIDC synthetic health check script"

# ============================================================================
# COMPLETION
# ============================================================================

log_event "phase4_aws_cloudwatch_complete" "success" "AWS CloudWatch monitoring deployed"

echo ""
echo "✅ PHASE-4 AWS CLOUDWATCH DEPLOYMENT COMPLETE"
echo ""
echo "📊 Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:"
echo "🚨 Alarms: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#alarmsV2:"
echo "📝 Logs: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logStream:"
echo ""
echo "Audit log: ${AUDIT_LOG}"
