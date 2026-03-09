# Rotation Runbook (Credential Systems)

Overview
--------
This runbook describes the on-call steps for credential rotation & health for GSM, Vault, and AWS KMS integrations.

Quick checks
------------
1. Verify Actions workflows are passing: `credential-refresh-15min`, `credential-health-check-hourly`, `credential-rotation-daily`.
2. Check latest audit logs in `scripts/audit/monitoring/` and `scripts/audit/archive/` for anomalies.
3. If a health-check fails, gather the last artifact from the failed run and attach to the incident.

Immediate mitigation
--------------------
- If GSM fails but Vault is healthy, promote Vault temporarily and open a P0 issue.
- If all providers fail, escalate to on-call and run emergency rollback following `Emergency-Procedure` (see repository DR playbook).

Running validation locally
-------------------------
```bash
bash scripts/rotation/run_integration_tests.sh
```

How to add a provider
---------------------
Follow `docs/ADD_CREDENTIAL_PROVIDER.md` for examples. After adding secrets to repository secrets, manually dispatch the `Validate Credential Providers` workflow from the Actions UI and attach artifacts to the resulting run.

Alerting
--------
PagerDuty integration is configured via repository secret `PAGERDUTY_TOKEN` and will be added to workflows when available.

Post-incident
-------------
Create a post-incident review issue linking to logs and remediation Draft issues. Ensure audit logs are archived and mark incident severity.
