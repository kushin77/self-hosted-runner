# Disaster Recovery Failover Test Procedures

**Document Version:** 1.0  
**Last Updated:** 2026-03-09  
**Frequency:** Quarterly (as part of compliance review)  
**Expected Duration:** 90-120 minutes per test  

---

## 🎯 Overview

This document provides step-by-step procedures for executing simulated failover tests as part of the quarterly DR and compliance review. These tests validate that the system can gracefully transition from primary infrastructure to backup/standby infrastructure while maintaining service availability.

### Objectives
1. Verify RTO (Recovery Time Objective) targets are met
2. Validate data consistency across failover boundary
3. Test communication paths and alerting mechanisms
4. Train operational teams on failover procedures
5. Identify gaps and improvements in DR processes
6. Maintain compliance with SLAs and regulatory requirements

### Scope
This procedure covers:
- Primary-to-backup infrastructure failover
- Traffic rerouting and load balancing
- Database replication & consistency verification
- Service restart and health checks
- User-facing impact assessment
- Rollback procedures

### Prerequisites
- [ ] All teams have read and approved this procedure
- [ ] Backup infrastructure is up-to-date and synchronized
- [ ] Monitoring and alerting is fully operational
- [ ] Stakeholders have been notified (no production impact window)
- [ ] Rollback plan is documented and tested
- [ ] Test window is scheduled during low-traffic period

---

## 📝 Pre-Test Checklist

### 72 Hours Before Test
- [ ] Notify all stakeholders that test will occur (email + Slack)
- [ ] Verify backup data freshness (within 1 hour if possible)
- [ ] Confirm all monitoring dashboards are operational
- [ ] Test communication channels (phone, Slack, email, war room)
- [ ] Brief all team members on their roles

### 24 Hours Before Test
- [ ] Verify primary system is fully operational
- [ ] Confirm backup system is healthy and synchronized
- [ ] Do final dry run of critical failover steps
- [ ] Prepare incident command structure (Incident Commander, scribe)
- [ ] Have rollback procedure printed/available

### 1 Hour Before Test
- [ ] All participants logged in and ready
- [ ] War room (physical or virtual) is open
- [ ] Scribe is standing by to document everything
- [ ] Monitoring dashboards visible on shared screen
- [ ] Rollback team is on standby

### 15 Minutes Before Test
- [ ] Final go/no-go decision by infrastructure lead
- [ ] All participants confirm readiness
- [ ] Set test start time and end time targets
- [ ] Begin recording meeting (if applicable)

---

## 🔄 Failover Test Procedures

### Phase 1: Baseline Measurement (15 minutes)
**Purpose:** Establish performance baseline before failover

**Steps:**
1. **Clear monitoring data** (optional, for cleaner visualization)
   ```bash
   # Document current time
   TEST_START_TIME=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
   echo "Test started at: $TEST_START_TIME"
   
   # Clear previous test data from monitoring if applicable
   # Example (Prometheus): curl -X POST http://prometheus:9090/-/admin/tsdb/delete_series
   ```

2. **Generate baseline traffic** (if applicable)
   - Run synthetic load test (10% of normal peak load)
   - Monitor current response times and error rates
   - Document baseline latency: _____ ms
   - Document baseline throughput: _____ requests/sec
   - Document baseline error rate: _____%

3. **Verify all services are healthy**
   - Check primary cluster status
   - Verify backup cluster status
   - Confirm database replication lag
   - Validate all health endpoints return "UP"

4. **Record baseline metrics**
   - CPU usage: Primary ___%, Backup ___%, Standby ___%
   - Memory usage: Primary ___%, Backup ___%, Standby ___%
   - Disk I/O latency: Primary ____ ms, Backup ____ ms
   - Network latency (primary → backup): ____ ms
   - Database replication lag: ____ seconds

---

### Phase 2: Failover Initiation (5 minutes)
**Purpose:** Transition traffic from primary to backup infrastructure

**Steps:**
1. **Get approval to proceed**
   - Incident Commander: "Ready to begin failover? (Y/N from all parties)"
   - Wait for confirmation from all participants
   - Document approval in meeting notes

2. **Mark test start in audit log**
   ```bash
   FAILOVER_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
   cat >> logs/failover-test-audit.jsonl << EOF
   {
     "timestamp": "${FAILOVER_START}",
     "event": "failover_initiated",
     "test_name": "Q1_2026_Quarterly_Review",
     "primary_system": "[PRIMARY_IDENTIFIER]",
     "target_system": "[BACKUP_IDENTIFIER]",
     "status": "started"
   }
   EOF
   ```

3. **Disable primary system from load balancer**
   - Option A (DNS): Change DNS record to point to backup IP
     ```bash
     # Execute DNS change (TTL should be low: 1 minute)
     aws route53 change-resource-record-sets \
       --hosted-zone-id [ZONE_ID] \
       --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"api.example.com","Type":"A","TTL":60,"ResourceRecords":[{"Value":"[BACKUP_IP]"}]}}]}'
     ```
   
   - Option B (Load Balancer): Remove primary pool members
     ```bash
     # Drain connections from primary
     kubectl drain [PRIMARY_NODE] --ignore-daemonsets --delete-emptydir-data
     
     # OR AWS Load Balancer:
     aws elbv2 deregister-targets --target-group-arn [ARN] \
       --targets Id=[PRIMARY_INSTANCE_ID]
     ```
   
   - Option C (Traffic Management): Update traffic policy
     ```bash
     # Update istio/linkerd/traefik routing policy
     kubectl apply -f - << EOF
     apiVersion: networking.istio.io/v1alpha3
     kind: VirtualService
     metadata:
       name: api-failover
     spec:
       hosts:
       - api.example.com
       http:
       - route:
         - destination:
             host: backup-svc
             port:
               number: 8080
           weight: 100
     EOF
     ```

4. **Activate backup system (if needed)**
   - Verify backup system is configured to accept traffic
   - Enable backup service endpoints
   - Verify connections from load balancer reach backup system
   - Confirm first traffic reaches backup within 60 seconds

5. **Note failover initiation time**
   - Record exact time DNS/LB change was applied: ___:___ UTC
   - Record time of first successful connection to backup: ___:___ UTC
   - Calculated "failover initiation delay": _____ seconds (SHOULD BE < 30 SEC)

---

### Phase 3: Traffic Verification (15 minutes)
**Purpose:** Verify traffic successfully shifted and services remain operational

**Steps:**
1. **Monitor traffic routing**
   - Watch connection count on backup system (should be increasing)
   - Verify connection count on primary drops to near zero
   - Monitor error rate (should remain close to baseline)

   ```bash
   # Monitor connections (example for Linux)
   while true; do
     echo "=== $(date) ==="
     echo "Primary connections: $(ss -s | grep TCP | awk '{print $3}')"
     echo "Backup connections: $(ssh backup-system 'ss -s' | grep TCP | awk '{print $3}')"
     echo "Error rate: $(curl -s http://backup-system:9090/api/v1/query?query=rate%5Bhttp_requests_total%5D | jq '.data.result[0].value[1]')"
     sleep 5
   done
   ```

2. **Verify application responses**
   - Send test requests to application endpoints
   - Verify responses are correct and timely
   - Check application logs for errors
   - Validate data returned matches expectations

   ```bash
   # Test application health
   for i in {1..10}; do
     echo "Health check $i:"
     curl -v http://api.example.com/health
     response_time=$?
     echo "Response time: ${response_time}ms"
     sleep 2
   done
   ```

3. **Validate database consistency**
   - Query both primary and backup databases
   - Compare data checksums (if possible)
   - Verify no data loss during failover
   - Check for replication lag

   ```bash
   # Verify database consistency
   PRIMARY_CHECKSUM=$(mysql -h primary.example.com -e "CHECKSUM TABLE database.table" | awk '{print $2}')
   BACKUP_CHECKSUM=$(mysql -h backup.example.com -e "CHECKSUM TABLE database.table" | awk '{print $2}')
   echo "Primary checksum: $PRIMARY_CHECKSUM"
   echo "Backup checksum: $BACKUP_CHECKSUM"
   if [ "$PRIMARY_CHECKSUM" = "$BACKUP_CHECKSUM" ]; then
     echo "✓ Databases are in sync"
   else
     echo "✗ DATABASE MISMATCH DETECTED - escalate immediately"
   fi
   ```

4. **Check system metrics under load**
   - CPU usage on backup: Should be similar to baseline (within 20%)
   - Memory usage on backup: Should be stable
   - Disk I/O latency: Should remain acceptable (< 2x baseline)
   - Network latency: Should be acceptable

5. **Verify alerting system activated**
   - Confirm monitoring system detected failover
   - Verify alerts were triggered (if configured)
   - Check that on-call team received notifications
   - Validate Slack/email notifications were sent

   ```bash
   # Check alert manager
   curl -s http://alertmanager:9093/api/v1/alerts | jq '.data[] | select(.labels.alert_type=="failover")'
   ```

---

### Phase 4: Extended Validation (30-45 minutes)
**Purpose:** Run extended tests to ensure backup can handle production workload

**Steps:**
1. **Customer-facing functionality tests**
   - Perform end-to-end transaction (if applicable)
   - Test user login/authentication
   - Execute key business workflows
   - Verify reporting/analytics
   - Test API integrations (if any)

2. **Backup system load testing** (optional but recommended)
   - Gradually increase simulated load to 25% of normal peak
   - Monitor system stability and metrics
   - Verify auto-scaling works (if applicable)
   - Confirm performance meets SLOs

   ```bash
   # Gradual load increase
   for load in 10 25 50 75 100; do
     echo "Increasing load to ${load}%..."
     # Run load generator at ${load}% intensity
     # Monitor for 5 minutes
     # Check error rates
     sleep 300
   done
   ```

3. **Audit logs verification**
   - Verify all transactions are being logged
   - Confirm audit trail integrity
   - Check that compliance logs are being written

4. **Certificate & credential verification**
   - Verify SSL/TLS certificates are valid
   - Confirm API keys are still valid on backup system
   - Validate database credentials work correctly

5. **Notification systems test**
   - Verify monitoring alerts work from backup system
   - Test log collection from backup
   - Confirm metrics are flowing to monitoring system

---

### Phase 5: Rollback Procedure (15-30 minutes)
**Purpose:** Return to primary system and verify recovery

**Steps:**
1. **Prepare for rollback**
   - Notify all participants: "Beginning rollback"
   - Verify primary system has recovered (if it was the issue)
   - Prepare rollback command(s)

   ```bash
   ROLLBACK_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
   echo "Rollback started at: $ROLLBACK_START"
   ```

2. **Drain connections from backup**
   - Stop accepting new connections on backup system
   - Allow existing connections 30-60 seconds to gracefully close

   ```bash
   # For Kubernetes:
   kubectl drain [BACKUP_NODE] --ignore-daemonsets --delete-emptydir-data
   
   # For custom systems:
   # Send SIGTERM to application (graceful shutdown)
   kill -TERM $(pgrep application-name)
   sleep 60
   ```

3. **Restore traffic to primary**
   - Re-enable primary system in load balancer
   - Update DNS record back to primary
   - Restore traffic routing policies

   ```bash
   # Example DNS restore
   aws route53 change-resource-record-sets \
     --hosted-zone-id [ZONE_ID] \
     --change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"api.example.com","Type":"A","TTL":60,"ResourceRecords":[{"Value":"[PRIMARY_IP]"}]}}]}'
   ```

4. **Verify traffic returned to primary**
   - Monitor connection count to primary (should increase)
   - Monitor connection count to backup (should decrease)
   - Verify error rate remains low

5. **Bring backup system back online** (if needed)
   - Re-enable backup system as standby
   - Verify it's receiving replication updates
   - Confirm backup is ready for next failover test

6. **Document rollback metrics**
   - Time to complete rollback: _____ seconds
   - Time for traffic to fully return: _____ seconds
   - Data consistency after rollback: [ ] OK [ ] ISSUES
   - Any services that need manual restart: _______

---

### Phase 6: Post-Test Analysis (15 minutes)
**Purpose:** Analyze results and identify improvements

**Steps:**
1. **Stop recording and document test end time**
   ```bash
   FAILOVER_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
   cat >> logs/failover-test-audit.jsonl << EOF
   {
     "timestamp": "${FAILOVER_END}",
     "event": "failover_completed",
     "status": "success",
     "total_duration_seconds": [CALCULATE],
     "findings": "[TBD - see detailed analysis below]"
   }
   EOF
   ```

2. **Compile performance metrics**
   - Total failover time (target: < 60 seconds): _____ seconds
   - Failover initiation delay (target: < 30 seconds): _____ seconds
   - Traffic verification time (target: < 300 seconds): _____ seconds
   - Rollback time (target: < 120 seconds): _____ seconds
   - Data loss: [ ] None [ ] Minor [ ] Major (ESCALATE)
   - Service availability during failover: _____%

3. **Review monitoring data**
   - Pull Prometheus/Grafana graphs of failover window
   - Capture error rate history
   - Document latency impact (if any)
   - Collect system metrics (CPU, memory, network)

4. **Review application logs**
   - Check for error spikes during failover
   - Look for failed connection attempts
   - Identify any services that didn't handle failover gracefully
   - Note any manual interventions needed

5. **Identify issues & create GitHub issues**
   - Any finding that doesn't meet targets → GitHub issue
   - Label: `compliance`, `dr`, `failover-test`
   - Set priority based on impact
   - Assign owner and target resolution date

   ```bash
   # Example issues to create (if applicable):
   # - "Failover took 2 min instead of 30 sec target"
   # - "Database showed 10 sec replication lag during failover"
   # - "Service X did not auto-restart on backup"
   # - "Alert threshold needs tuning for faster detection"
   ```

6. **Lessons learned discussion**
   - What went well?
   - What could be improved?
   - Were there any surprises?
   - Should we change RTO/RPO targets?
   - Do we need infrastructure changes?

---

## ✅ Post-Test Checklist

- [ ] All test procedures completed successfully
- [ ] Performance metrics documented
- [ ] Rollback to primary system verified
- [ ] All services operational on primary
- [ ] Backup system ready for next test
- [ ] GitHub issues created for any findings
- [ ] Test report distributed to stakeholders
- [ ] Meeting minutes archived
- [ ] Audit logs saved to `logs/failover-test-audit.jsonl`

---

## 📊 Failover Test Report Template

Generate this report after each test and attach to GitHub issue #2052:

```markdown
# Failover Test Report - Q[X] 2026

**Test Date:** [DATE]  
**Test Duration:** [DURATION]  
**Incident Commander:** [NAME]  
**Status:** [✓ SUCCESS / ⚠ PARTIAL / ✗ FAILED]  

## Executive Summary
[2-3 sentence summary of test results]

## Performance Metrics
| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Failover Time | < 60s | [X]s | [✓/✗] |
| Failover Initiation | < 30s | [X]s | [✓/✗] |
| Data Loss | 0 | [X] | [✓/✗] |
| Availability During Failover | 99.9% | [X]% | [✓/✗] |
| Rollback Time | < 120s | [X]s | [✓/✗] |

## Key Findings
1. [Finding 1]
2. [Finding 2]
3. [Finding 3]

## Issues Identified
- [GitHub Issue Link 1]
- [GitHub Issue Link 2]
- [GitHub Issue Link 3]

## Recommendations
- [Recommendation 1]
- [Recommendation 2]
- [Recommendation 3]

## Approved By
- [ ] Infrastructure Lead
- [ ] Compliance Officer
- [ ] Operations Manager

**Report Generated:** [DATE]  
**Next Test:** Q[X+1] 2026 ([DATE RANGE])
```

---

## 🚨 Incident Escalation

If during the test you encounter any of the following, **STOP THE TEST** and escalate:

1. **Data Loss**: Any indication that data was lost during failover
2. **Uncontrolled Failover**: System failed over without permission
3. **Database Corruption**: Data inconsistency between primary and backup
4. **Critical Service Down**: Application is completely unreachable
5. **Security Breach**: Unauthorized access detected during test

**Escalation Path:**
1. Incident Commander calls for test halt
2. CTO/Infrastructure Lead notified immediately
3. War room discussion on severity
4. Create CRITICAL GitHub issue if applicable
5. Execute emergency rollback if needed

---

## 📝 Reference Documents

- DR_COMPLIANCE_QUARTERLY_REVIEW_CHECKLIST.md
- QUARTERLY_DR_COMPLIANCE_CALENDAR_SCHEDULE.md
- [Link to Production Runbook]
- [Link to Incident Response Plan]
- [Link to Infrastructure Documentation]

---

## 🔄 Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-03-09 | Operations Team | Initial creation |

---

**Status:** Ready for Q1 2026 Failover Test  
**Next Review:** April 2026 (Q2)
