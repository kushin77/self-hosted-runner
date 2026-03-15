# Redeploy 100X Gap Analysis

- Timestamp (UTC): 2026-03-15T03:29:52Z
- Environment: production
- Domain: elevatediq.ai
- Target Worker Host: 192.168.168.42
- NAS Host: 192.168.168.100
- Dry Run: true

## Failures
- Host policy enforcement

## Warnings
- Domain drift detected outside elevatediq.ai. Review report for exact files.
- Generated .env from .env.example. Fill secrets before non-dry-run deployment.
- Duplicate script basenames detected. See /home/akushnir/self-hosted-runner/reports/redeploy/duplicate-script-basenames-20260315-032951.txt
- Potential secret exposure patterns detected.
- Found service-account naming that may be outside elevatediq-svc-* standard
- Syntax check report has findings: /home/akushnir/self-hosted-runner/reports/redeploy/syntax-check-20260315-032951.txt

## Delta Summary
- Process: centralized entrypoint in scripts/redeploy
- Consistency: env and template checks enforced
- Security: pattern-based exposure scan executed
- Governance: issue/epic generation integrated
- Backups: NAS to GCP daily+weekly retention policy validated
