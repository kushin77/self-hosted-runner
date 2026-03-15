# Redeploy 100X Gap Analysis

- Timestamp (UTC): 2026-03-15T03:30:03Z
- Environment: production
- Domain: elevatediq.ai
- Target Worker Host: 192.168.168.42
- NAS Host: 192.168.168.100
- Dry Run: true

## Failures
- None

## Warnings
- Running in dry-run on forbidden deploy host (192.168.168.31). Full deployment remains blocked.
- Domain drift detected outside elevatediq.ai. Review report for exact files.
- Duplicate script basenames detected. See /home/akushnir/self-hosted-runner/reports/redeploy/duplicate-script-basenames-20260315-033003.txt
- Potential secret exposure patterns detected.
- Found service-account naming that may be outside elevatediq-svc-* standard
- Syntax check report has findings: /home/akushnir/self-hosted-runner/reports/redeploy/syntax-check-20260315-033003.txt

## Delta Summary
- Process: centralized entrypoint in scripts/redeploy
- Consistency: env and template checks enforced
- Security: pattern-based exposure scan executed
- Governance: issue/epic generation integrated
- Backups: NAS to GCP daily+weekly retention policy validated
