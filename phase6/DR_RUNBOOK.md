# Disaster Recovery & Business Continuity (Phase 6)

Purpose: automated backup/restore validation, failover drills, cross-region restore playbooks.

1. Backup policy
  - Daily full snapshot to multi-region GCS/S3
  - Hourly incremental for critical DBs
  - Store encryption keys in KMS; rotation policy applied

2. Automated DR scripts
  - `scripts/phase6/dr_backup_test.sh` — create test backup, restore into isolated namespace, run validation tests
  - `scripts/phase6/dr_failover.sh` — promote replica in another region (requires operator approval)

3. Recovery tests
  - Quarterly full-restore drills
  - Monthly restore smoke tests

4. RTO/RPO targets
  - RTO: 1 hour for critical services
  - RPO: 15 minutes for critical data
