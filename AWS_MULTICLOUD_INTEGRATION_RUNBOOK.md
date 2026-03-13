# AWS & Multi-Cloud Integration Operator Runbook

## Overview

This runbook covers the AWS and multi-cloud integration components for the zero-trust infrastructure:

- **AWS Integration** (`security/aws-integration.sh`) — AWS credentials, KMS, and CloudWatch
- **Multi-Cloud Failover** (`security/multi-cloud-failover.sh`) — 4-layer credential retrieval with SLA guarantees

---

## Quick Start

### 1. Validate AWS Setup

```bash
cd /home/akushnir/self-hosted-runner
bash security/aws-integration.sh validate
```

Expected output if credentials are placeholders:
```
[AWS-INTEGRATION] Validating AWS integration setup...
[AWS-INTEGRATION] Validating AWS identity...
[WARN] AWS credentials are placeholder values
[WARN] To populate real credentials:
[WARN]   1. Generate AWS access key in AWS Console
[WARN]   2. gcloud secrets versions add aws-access-key-id ...
[WARN]   3. gcloud secrets versions add aws-secret-access-key ...
[INFO] ✓ AWS integration validated
```

### 2. Populate Real AWS Credentials

When you have real AWS credentials from your AWS account:

```bash
# Add access key ID to GSM
echo -n "AKIAXXXXXXXXXXXXXXXX" | \
  gcloud secrets versions add aws-access-key-id \
    --data-file=- \
    --project=nexusshield-prod

# Add secret access key to GSM
echo -n "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" | \
  gcloud secrets versions add aws-secret-access-key \
    --data-file=- \
    --project=nexusshield-prod

# Verify
bash security/aws-integration.sh validate
```

### 3. Set Up AWS Infrastructure

```bash
# Set up KMS, CloudWatch, and S3 Object Lock
export GCP_PROJECT=nexusshield-prod
export AWS_REGION=us-east-1
bash security/aws-integration.sh setup
```

This will:
- ✓ Create KMS key for secret encryption
- ✓ Configure CloudWatch monitoring IAM role
- ✓ Set up S3 Object Lock WORM bucket (365-day retention)

### 4. Test Multi-Cloud Failover

```bash
# Health check all credential layers
bash security/multi-cloud-failover.sh health

# Retrieve specific secret with automatic failover
bash security/multi-cloud-failover.sh failover github-token

# View SLA configuration
bash security/multi-cloud-failover.sh sla-report
```

---

## Architecture

### Multi-Cloud Credential Failover (4 Layers)

```
┌─────────────────────────────────────────────────────┐
│         Secret Retrieval Request                    │
└──────────────────┬──────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
   ┌────▼─────┐          ┌────▼─────┐
   │ Layer 1   │          │ Connected?
   │ AWS STS   │          │ (250ms)
   │ Direct    │          │
   │(250ms)    │          │Success
   └─────┬─────┘          └────┬─────┘
         │                     │
      Fail                     │
         │                  ┌──▼──────────┐
         │                  │ Layer 2:     │
         │    ┌─────────────│ GSM          │
         │    │             │ (2.85s)      │
         └────┼──────┐      └──┬───────────┘
              │      │         │
           Timeout   │      Success
              │   Fail          │
              │      │       ┌──▼──────────┐
              │      └──────▶│ Layer 3:     │
              │              │ Vault        │
              │              │ (4.2s)       │
              │              └──┬───────────┘
              │                 │
              │              Timeout
              │                 │
              │              ┌──▼──────────┐
              └─────────────▶│ Layer 4:     │
                             │ AWS KMS      │
                             │ (50ms)       │
                             └──┬───────────┘
                                │
                             Return
                             Secret
```

**SLA Targets:**
- Layer 1 (AWS STS): 250ms — Fastest, AWS-managed credentials
- Layer 2 (GSM): 2.85s — Primary, GCP-managed secrets
- Layer 3 (Vault): 4.2s — Secondary, self-hosted backend
- Layer 4 (AWS KMS): 50ms — Encrypted offline backup
- **Overall SLA: 4.2 seconds** (maximum total time to retrieve any secret)

---

## Daily Operations

### Morning Verification

```bash
# Run service health checks
bash security/verify-deployment.sh

# Run credential failover health check
bash security/multi-cloud-failover.sh health

# Verify Cloud Run service
curl -v https://zero-trust-auth-2tqp6t4txq-uc.a.run.app/health

# Check GSM secret health
bash scripts/ci/verify_gsm_secrets.sh
```

### Credential Rotation (Every 90 Days)

```bash
# Generate new AWS credentials in AWS Console
# Download keys safely to secure terminal

# Rotate primary credentials
bash security/aws-integration.sh rotate
gcloud secrets versions add aws-access-key-id --data-file=<(echo -n "NEW_KEY")
gcloud secrets versions add aws-secret-access-key --data-file=<(echo -n "NEW_SECRET")

# Verify new credentials work
bash security/aws-integration.sh validate

# Disable old credentials in AWS Console
# Update any downstream systems using old key
```

### Troubleshooting

#### Credentials Not Working

```bash
# Check what's in GSM
gcloud secrets versions list aws-access-key-id --project=nexusshield-prod
gcloud secrets versions list aws-secret-access-key --project=nexusshield-prod

# Verify non-placeholder values
kid=$(gcloud secrets versions access latest --secret=aws-access-key-id --project=nexusshield-prod)
echo "Key starts with: ${kid:0:4}"  # Should be "AKIA" not "PLAC"

# Test retrieval directly
bash security/multi-cloud-failover.sh failover aws-access-key-id

# Enable verbose logging
bash -x security/aws-integration.sh validate
```

#### GSM Layer Not Responding

```bash
# Test GSM access
gcloud secrets versions access latest --secret=aws-access-key-id --project=nexusshield-prod

# Check gcloud auth
gcloud auth list
gcloud auth application-default login

# Verify project access
gcloud config get-value project
```

#### Vault Layer Timeout

```bash
# Check Vault connectivity
export VAULT_ADDR="https://vault.example.com:8200"
export VAULT_TOKEN="hvs...."

curl -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/health"

# Check network/firewall
nc -zv vault.example.com 8200
```

#### KMS Decryption Failed

```bash
# Verify KMS key exists
aws kms list-aliases --region us-east-1 | grep nexusshield

# Check encrypted backup files
ls -la /var/lib/nexusshield/encrypted/

# Verify IAM permissions
aws iam get-user-policy --user-name <service-account> --policy-name kms-policy
```

---

## Advanced Configuration

### Custom KMS Key

```bash
# Use existing KMS key
export AWS_KMS_KEY_ALIAS="arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
bash security/aws-integration.sh setup
```

### Enable Vault Fallback

```bash
# Set up Vault configuration
export VAULT_ADDR="https://vault.prod.example.com:8200"
export VAULT_TOKEN="hvs.CAESIGuPvv..."

# Test Vault retrieval
bash security/multi-cloud-failover.sh failover terraform-signing-key
```

### Configure CloudWatch Alarms

```bash
# Create alarm for credential retrieval failures
aws cloudwatch put-metric-alarm \
  --alarm-name nexusshield-credential-failures \
  --alarm-description "Alert on credential retrieval failures" \
  --metric-name CredentialRetrievalFailures \
  --namespace NexusShield \
  --statistic Sum \
  --period 60 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold
```

### Enable S3 Object Lock Enforcement

```bash
# Verify S3 bucket is in COMPLIANCE mode
aws s3api get-object-lock-configuration \
  --bucket nexusshield-audit-trail

# Expected output:
# {
#   "ObjectLockConfiguration": {
#     "ObjectLockEnabled": "Enabled",
#     "Rule": {
#       "DefaultRetention": {
#         "Mode": "COMPLIANCE",
#         "Days": 365
#       }
#     }
#   }
# }
```

---

## Monitoring & Observability

### Key Metrics to Track

1. **Credential Retrieval Latency**
   - Layer 1 (STS): < 250ms
   - Layer 2 (GSM): < 2850ms
   - Layer 3 (Vault): < 4200ms
   - Layer 4 (KMS): < 50ms

2. **Failover Events**
   - How many times each layer was used
   - Fallback frequency
   - Success rate per layer

3. **Credential Expiration**
   - Days until rotation needed
   - AWS access key age
   - GSM secret version count

### CloudWatch Integration

```bash
# View credential retrieval metrics
aws cloudwatch get-metric-statistics \
  --namespace NexusShield \
  --metric-name CredentialRetrievalLatency \
  --start-time 2026-03-13T00:00:00Z \
  --end-time 2026-03-14T00:00:00Z \
  --period 300 \
  --statistics Average,Maximum,Minimum
```

### Prometheus Metrics (If Using Prometheus/Grafana)

Create custom metrics:
```yaml
nexusshield_credential_retrieval_ms{layer="gsm",secret="github-token"} 145
nexusshield_credential_retrieval_ms{layer="vault",secret="terraform-key"} 3820
nexusshield_failover_events_total{from_layer="gsm",to_layer="vault"} 3
```

---

## Integration with Zero-Trust Service

The Cloud Run zero-trust service automatically uses the failover system:

```typescript
// In security/zero-trust-auth.ts
async function getCredential(name: string): Promise<string> {
  // Automatically cascades through layers:
  // 1. AWS STS (if available)
  // 2. GSM (primary)
  // 3. Vault (secondary)
  // 4. KMS (backup)
  return await execSync(`bash security/multi-cloud-failover.sh failover ${name}`);
}
```

---

## Security Best Practices

### ✅ DO

- ✓ Rotate credentials every 90 days
- ✓ Use placeholder values during development
- ✓ Enable CloudWatch monitoring for all retrieval failures
- ✓ Test failover scenarios weekly
- ✓ Keep GSM secrets updated with latest versions
- ✓ Audit credential access logs in Cloud Logging

### ❌ DON'T

- ✗ Store credentials in environment variables
- ✗ Log credentials in output (they're redacted automatically)
- ✗ Share AWS credentials via Slack/email
- ✗ Use same credentials across environments
- ✗ Disable S3 Object Lock once enabled
- ✗ Keep expired keys in GSM (archive old versions)

---

## Emergency Procedures

### Suspected Credential Compromise

```bash
# 1. Identify compromised credential
credential="aws-access-key-id"

# 2. Revoke in source system
aws iam delete-access-key --access-key-id AKIAXXXXXXXX

# 3. Generate new credential in AWS Console
# (Copy safely to secure terminal)

# 4. Update in GSM
gcloud secrets versions add "$credential" --data-file=<(echo -n "NEW_KEY")

# 5. Verify new credential works
bash security/aws-integration.sh validate

# 6. Audit access logs
gcloud logging read "protoPayload.resourceName=~\"$credential\"" \
  --limit 100 \
  --format json

# 7. Notify security team
# (Post incident in #security channel)
```

### Complete Failover Failure

If all 4 credential layers fail:

```bash
# 1. Check system health
bash security/verify-deployment.sh

# 2. Verify GSM is accessible
gcloud secrets list --project=nexusshield-prod

# 3. Check GCP authentication
gcloud auth list
gcloud auth activate-service-account --key-file=/path/to/sa-key.json

# 4. Verify AWS CLI is installed
aws --version
aws sts get-caller-identity

# 5. If still failing, switch to manual credential retrieval
kid=$(gcloud secrets versions access latest --secret=aws-access-key-id --project=nexusshield-prod)
sec=$(gcloud secrets versions access latest --secret=aws-secret-access-key --project=nexusshield-prod)
export AWS_ACCESS_KEY_ID="$kid"
export AWS_SECRET_ACCESS_KEY="$sec"
aws sts get-caller-identity
```

---

## References

- **AWS Documentation:** https://docs.aws.amazon.com/
- **Google Secret Manager:** https://cloud.google.com/secret-manager
- **HashiCorp Vault:** https://www.vaultproject.io/
- **Zero-Trust Architecture:** See ARCHITECTURE_COMPLIANCE_CERTIFICATION_2026_03_11.md

---

**Last Updated:** March 13, 2026  
**Status:** Production Ready  
**Maintained by:** Infrastructure Team
