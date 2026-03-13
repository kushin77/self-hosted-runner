# Deployment Issues — Action Items

## Issue: Cloudflare API token missing in GSM
- Status: OPEN
- Description: `cloudflare-api-token` secret not found in Google Secret Manager for project `nexusshield-prod`. Full DNS promotion cannot proceed without this token.
- Required action: Operator must create/update secret `cloudflare-api-token` in GSM with a token that has **Zone.DNS Write** permissions.
- Steps:
  1. GCP Console → Security → Secret Manager → Select project `nexusshield-prod`
  2. Create secret named `cloudflare-api-token` (or add new version if exists)
  3. Paste token value and save
  4. Notify automation system to resume (or the automation will poll and resume)

## Issue: Slack webhook placeholder
- Status: OPTIONAL
- Description: `slack-webhook` secret exists but may be placeholder. Verify and update if real notifications required.

## Issue: AWS CLI credentials for Route53 fallback
- Status: OPTIONAL
- Description: AWS CLI not authenticated in current session. If Route53 fallback is desired, provide AWS credentials in GSM or configure the bastion's IAM/credentials.
