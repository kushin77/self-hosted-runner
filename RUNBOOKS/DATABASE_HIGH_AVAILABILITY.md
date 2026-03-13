# NexusShield Database High Availability Runbook

## Overview

This runbook documents the Cloud SQL high availability setup for NexusShield Portal with:
- **Primary Database**: us-central1 (REGIONAL with ZONAL redundancy)
- **Standby Replica**: us-west1 (FAILOVER_REPLICA)
- **Replication**: Synchronous (RTO: 5 min, RPO: 0 min)
- **SLA**: 99.999% uptime

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Deployment Verification](#deployment-verification)
3. [Failover Procedures](#failover-procedures)
4. [Monitoring and Alerts](#monitoring-and-alerts)
5. [Troubleshooting](#troubleshooting)
6. [Runbook Index](#runbook-index)

---

## Architecture Overview

### Primary Region (us-central1)
```
┌─────────────────────────────────────┐
│ Cloud SQL Primary Instance          │
│ - POSTGRES_14                       │
│ - REGIONAL HA (multi-zone)          │
│ - Synchronous Replication Enabled   │
│ - Automated Backups (Daily)         │
│ - Point-in-Time Recovery (7 days)   │
└─────────────────────────────────────┘
         ↕ Synchronous Replication
┌─────────────────────────────────────┐
│ Cloud SQL Standby Replica           │
│ - us-west1                          │
│ - FAILOVER_REPLICA                  │
│ - Read-only (until failover)        │
│ - Automatic promotion on failure    │
└─────────────────────────────────────┘
```

### Failover Behavior
- **Automatic Failover**: Triggered if primary is unavailable > 5 minutes
- **Zero Data Loss**: Synchronous replication ensures RPO = 0
- **Application Reconnection**: Update connection string to standby after failover

---

## Deployment Verification

### 1. Check Instance Status

```bash
# List all Cloud SQL instances
gcloud sql instances list --format="table(name, databaseVersion, region, state)"

# Check primary instance
gcloud sql instances describe nexusshield-db-primary-PROJECT_ID

# Check standby instance
gcloud sql instances describe nexusshield-db-standby-PROJECT_ID
```

### 2. Verify Replication Status

```bash
# Connect to primary database
gcloud sql connect nexusshield-db-primary-PROJECT_ID \
  --user=postgres

# Inside psql, check replication status
SELECT * FROM pg_stat_replication;
SELECT client_addr, backend_start, state, WAL_lsn FROM pg_stat_replication;

# Check replication lag (should be near 0)
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;

# Verify synchronous replication is enabled
SHOW synchronous_commit;
SELECT name, setting FROM pg_settings WHERE name LIKE '%replication%';
```

### 3. Verify Failover Configuration

```bash
# Check if standby is configured for failover
gcloud sql instances describe nexusshield-db-standby-PROJECT_ID \
  --format="value(masterInstanceName, replicaConfiguration)"

# Verify automatic failover flag
gcloud sql instances describe nexusshield-db-primary-PROJECT_ID \
  --format="value(settings.backupConfiguration.backup_retention_settings)"
```

### 4. Test Connection Strings

```bash
# Primary connection (applications use this)
export PRIMARY_IP=$(gcloud sql instances describe nexusshield-db-primary-PROJECT_ID \
  --format="value(ipAddresses[0].ipAddress)")
echo "Primary IP: $PRIMARY_IP"

# Standby connection (for manual read-only access)
export STANDBY_IP=$(gcloud sql instances describe nexusshield-db-standby-PROJECT_ID \
  --format="value(ipAddresses[0].ipAddress)")
echo "Standby IP: $STANDBY_IP"
```

---

## Failover Procedures

### Automatic Failover (System-Initiated)

When the primary instance becomes unavailable:

1. **Detection Phase** (0-5 minutes)
   - Cloud SQL monitors primary instance health
   - Multiple failed health checks trigger failover decision
   - Notifications sent to ops channel

2. **Promotion Phase** (5-10 minutes)
   - Standby promoted to primary
   - New primary accepts write operations
   - Old primary remains offline
   - DNS updated (if using Cloud DNS)

3. **Recovery Phase** (10-30 minutes)
   - Applications reconnect to new primary
   - Monitoring confirms new primary is healthy
   - Restore old primary as new standby (optional)

### Manual Failover (Operator-Initiated)

**When to use:**
- Planned maintenance on primary
- Major version updates required
- Security patches on primary
- Testing failover procedures (staging only!)

**Steps:**

```bash
# 1. Prepare for failover
export PROJECT_ID=$(gcloud config get-value project)
export PRIMARY_NAME="nexusshield-db-primary-${PROJECT_ID}"
export STANDBY_NAME="nexusshield-db-standby-${PROJECT_ID}"

# 2. Verify standby is healthy and replication is caught up
gcloud sql instances describe $STANDBY_NAME

# 3. Initiate failover (THIS WILL PROMOTE STANDBY TO PRIMARY)
gcloud sql instances failover $PRIMARY_NAME

# 4. Wait for failover to complete (typically 5-10 minutes)
watch gcloud sql instances describe $PRIMARY_NAME --format="value(state)"

# 5. Verify new primary is accepting connections
gcloud sql connect $PRIMARY_NAME --user=postgres -c "SELECT now();"

# 6. Update application connection strings to point to new primary

# 7. Create new standby from new primary (optional, for redundancy)
# Contact DevOps team to provision new standby instance in different region
```

### Failback to Original Primary

After the original primary recovers:

```bash
# Option A: Keep current configuration (standby becomes new primary)
# - No action needed, everything continues working

# Option B: Failback to original primary (only if required)
# This requires manual coordination:
# 1. Stop all writes to current primary
# 2. Wait for standby replication to catch up
# 3. Perform second failover to return to original primary
# 4. Verify application stability
# 5. Resume normal operations
```

---

## Monitoring and Alerts

### Key Metrics to Monitor

```bash
# 1. Replication Lag
gcloud monitoring metrics-descriptors list \
  --filter="displayName:CloudSQL*replication*"

# Query replication lag via Cloud Monitoring
# Metric: cloudsql.googleapis.com/network/replication_lag
# Threshold: > 5 seconds (alert)

# 2. CPU Utilization
# Metric: cloudsql.googleapis.com/database/cpu/utilization
# Threshold: > 80% (warning), > 95% (critical)

# 3. Disk Utilization
# Metric: cloudsql.googleapis.com/database/disk/utilization
# Threshold: > 85% (warning), > 95% (critical)

# 4. Memory Utilization
# Metric: cloudsql.googleapis.com/database/memory/utilization
# Threshold: > 90% (warning)

# 5. Connections
# Metric: cloudsql.googleapis.com/database/postgresql/num_backends
# Alert if approaching max (500 configured)

# 6. Connections - Replication
# Metric: cloudsql.googleapis.com/database/replication/replica_lag
# Alert if lag > 10 seconds
```

### Set Up Alert Policies

```bash
# Create alert policy for replication lag
gcloud alpha monitoring policies create \
  --notification-channels=CHANNEL_ID \
  --display-name="Cloud SQL Replication Lag Alert" \
  --condition-display-name="Replication lag > 5 seconds" \
  --condition-expression='resource.type="cloudsql_database" AND metric.type="cloudsql.googleapis.com/network/replication_lag" AND metric.value > 5'

# Create alert policy for disk usage
gcloud alpha monitoring policies create \
  --notification-channels=CHANNEL_ID \
  --display-name="Cloud SQL Disk Usage Alert" \
  --condition-display-name="Disk > 85% utilized" \
  --condition-expression='resource.type="cloudsql_database" AND metric.type="cloudsql.googleapis.com/database/disk/utilization" AND metric.value > 0.85'

# Create alert policy for primary failure
gcloud alpha monitoring policies create \
  --notification-channels=CHANNEL_ID \
  --display-name="Cloud SQL Primary Instance Down" \
  --condition-display-name="Primary not running" \
  --condition-expression='resource.type="cloudsql_database" AND resource.labels.database_id=~".*primary.*" AND metric.type="cloudsql.googleapis.com/database/up" AND metric.value < 1'
```

### Viewing Logs

```bash
# Query Cloud Logging for database events
gcloud logging read "resource.type=cloudsql_database" \
  --limit 50 \
  --format=json \
  --project=PROJECT_ID

# Filter for failover events
gcloud logging read "resource.type=cloudsql_database AND protoPayload.methodName:failover" \
  --limit 20 \
  --project=PROJECT_ID

# Filter for replication errors
gcloud logging read "resource.type=cloudsql_database AND severity=ERROR AND textPayload:replication" \
  --limit 20 \
  --project=PROJECT_ID
```

---

## Troubleshooting

### Issue: Replication Lag > 5 Seconds

**Cause:** Network latency, primary database overload, or standby resource constraints

**Resolution:**

```bash
# 1. Check primary database load
gcloud sql instances describe $PRIMARY_NAME \
  --format="value(settings.tier)" # Should be n1-standard-2 or larger

# 2. Check standby database resources
gcloud sql instances describe $STANDBY_NAME \
  --format="value(settings.tier)"

# 3. Check CPU and memory utilization
gcloud monitoring time-series list \
  --filter='metric.type="cloudsql.googleapis.com/database/cpu/utilization" AND resource.labels.database_id=~".*primary.*"'

# 4. If lag persists, consider:
# - Scaling up primary instance tier
# - Reducing max connections
# - Optimizing slow queries (check slow query log)
# - Reducing transaction batch sizes

# 5. Monitor replication status in database
gcloud sql connect $PRIMARY_NAME --user=postgres -c "SELECT * FROM pg_stat_replication;"
```

### Issue: Failover Not Triggering Automatically

**Cause:** Primary instance shows as "healthy" but is not accepting connections

**Resolution:**

```bash
# 1. Force health check on primary
gcloud sql instances restart $PRIMARY_NAME

# 2. Wait 30 seconds for health check to update
sleep 30

# 3. Check if automatic failover is enabled
gcloud sql instances describe $PRIMARY_NAME \
  --format="value(settings.backupConfiguration)"

# 4. If still not failing over, trigger manual failover
gcloud sql instances failover $PRIMARY_NAME

# 5. Check logs for failover events
gcloud logging read "resource.type=cloudsql_database AND protoPayload.methodName:failover" \
  --limit 5 \
  --format=json
```

### Issue: Cannot Connect to Standby After Failover

**Cause:** Connection strings still pointing to old primary, or network connectivity issues

**Resolution:**

```bash
# 1. Get the new primary IP address
gcloud sql instances describe $PRIMARY_NAME \
  --format="value(ipAddresses[0].ipAddress)"

# 2. Update connection strings in application config
# Before: 10.1.x.x (old primary)
# After: 10.2.x.x (new primary in us-west1)

# 3. Test connection from application server
psql -h NEWPRIMARYIP -U postgres -d nexusshield -c "SELECT now();"

# 4. Verify Cloud SQL Proxy is updated (if using proxy)
pkill cloudsql-proxy
/cloud_sql_proxy -instances=PROJECT_ID:us-west1:NEWPRIMARYNAME &

# 5. Check network firewall rules
gcloud compute firewall-rules list --filter="name:nexusshield*"
```

### Issue: Replication Broken After Failback

**Cause:** Data divergence between old primary and new primary during failover

**Resolution:**

```bash
# 1. Do NOT attempt to bring old failover replica back as standby

# 2. Instead, create a fresh replica from new primary
# This will ensure data consistency

# 3. If replication still broken, rebuild standby:
#    - Delete old standby instance
#    - Create new replica from primary
#    - Monitor replication status

# Contact DevOps team for assistance:
# Rebuilding standby requires:
# - ~30 minutes of initial DB copy
# - Brief spike in network traffic (500GB+ database)
```

---

## Runbook Index

### Quick Reference

| Scenario | Command | Notes |
|----------|---------|-------|
| Check status | `gcloud sql instances list` | See instance states |
| View replication lag | `SELECT now() - pg_last_xact_replay_timestamp()` | Should be < 1 second |
| Manual failover | `gcloud sql instances failover PRIMARY_NAME` | Promotes standby to primary |
| Check alerts | `gcloud alpha monitoring policies list` | View alert policies |
| Export backup | `gcloud sql backups create --instance=PRIMARY_NAME` | Create on-demand backup |
| Restore backup | `gcloud sql backups restore BACKUP_ID --instance=PRIMARY_NAME` | Restore specific backup |
| View logs | `gcloud logging read "resource.type=cloudsql_database"` | CloudSQL audit logs |

### Related Documentation

- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [High Availability Best Practices](https://cloud.google.com/sql/docs/postgres/high-availability)
- [Disaster Recovery](https://cloud.google.com/sql/docs/postgres/backup-recovery)
- [PostgreSQL 14 Reference](https://www.postgresql.org/docs/14/reference.html)

### Support Contacts

- **DevOps Team**: devops@nexusshield.cloud
- **On-Call**: Check PagerDuty schedule
- **Emergency**: Contact ISP for network issues

---

## Appendix: Terraform Deployment

### Deploy HA Configuration

```bash
cd terraform

# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=ha-db.plan -var="ha_environment=production"

# Review plan output
cat ha-db.plan

# Apply configuration
terraform apply ha-db.plan

# Verify resources created
terraform show
```

### Scaling the Database

```bash
# Upgrade instance tier (requires downtime for primary)
terraform apply -var="database_machine_type=db-n1-standard-4"

# Increase disk size
terraform apply -var="disk_size_gb=200"

# Both configurations scale automatically for standby
```

---

**Last Updated:** 2026-03-13  
**Maintained By:** DevOps Team  
**Reviewed:** Monthly
