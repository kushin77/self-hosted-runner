Title: Provision AWS Secrets Manager credentials for runner

Status: Open

Description:
The watcher requires AWS credentials or an instance role to read `runner/ssh-credentials` from AWS Secrets Manager.

Action items:
- Configure AWS credentials with `secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret` for the watcher.
- Option A (preferred): Attach an IAM role to the bastion/worker instance with a policy granting access to `arn:aws:secretsmanager:*:*:secret:runner/*` and `kms:Decrypt` as needed.
- Option B: Create an IAM user and provide `AWS_ACCESS_KEY_ID`/`REDACTED_AWS_SECRET_ACCESS_KEY` to the watcher via systemd environment (less secure).

Notes:
- The repository contains `scripts/aws-bootstrap.sh` to create/update the secret once credentials are available.
- The watcher supports auto-detection and will use AWS when credentials are present.

Assigned-to: ops-team
Priority: High