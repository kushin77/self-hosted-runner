## EPIC-6: AWS & GCP Bootstrap (quick start)

This document explains the first-step bootstrap for EPIC-6: provisioning AWS IAM credentials and mapping them into the multi-layer secret system (GSM → Vault → KMS). It is idempotent and designed for automated runs.

AWS bootstrap (summary):
- Prepare `policy.json` that defines the least-privilege policy for the operator user.
- Run `scripts/aws/setup-aws-iam-role.sh --iam-policy-file policy.json --project nexusshield-prod --username epic6-operator`.
- The script will create an IAM user, attach the policy, create access keys and store them in GSM and Vault at `secret/aws/epic6`.

Runtime usage:
```
source scripts/aws/aws-credentials.sh
aws sts get-caller-identity
```

Next steps (GCP): add service account bootstrap mirroring this pattern.
