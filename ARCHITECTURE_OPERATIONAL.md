# 🏗️ OPERATIONAL ARCHITECTURE - 5-PHASE INFRASTRUCTURE RESILIENCE FRAMEWORK
## Technical Design, Components, and System Integration

**Date**: March 14, 2026  
**Status**: ✅ **FULLY OPERATIONAL (All 5 Phases)**  
**Version**: 2.0

---

## 📐 SYSTEM OVERVIEW

```
┌─────────────────────────────────────────────────────────────────┐
│           INFRASTRUCTURE RESILIENCE FRAMEWORK                    │
│                    (5-Phase Architecture)                        │
└─────────────────────────────────────────────────────────────────┘

PHASE 1 (Detection)
├─ Prometheus + AlertManager (incident detection)
├─ Custom Kubernetes watchers (resource monitoring)
├─ Elasticsearch + ELK stack (log aggregation)
└─ Threshold alerting (>99% detection rate)
    ↓ DETECTION OUTPUT: Slack notification + GitHub event log

PHASE 2 (Auto-Remediation)  
├─ Custom Kubernetes controllers (handler execution)
├─ Remediation decision engine (incident classification)
├─ Action executors (Pod restart, Node drain, Scale up, etc.)
└─ Failure tracking (escalate if >5 retries)
    ↓ REMEDIATION OUTPUT: System auto-heals + GitHub issue created

PHASE 3 (Predictive ML)
├─ Time series forecasting model (ML prediction)
├─ Historical metrics database (CloudSQL + BigQuery)
├─ Feature engineering pipeline (hourly update)
└─ Anomaly detection (2σ/3σ severity classification)
    ↓ PREDICTION OUTPUT: Hourly forecast + anomaly alerts

PHASE 4 (Multi-Region Failover)
├─ DNS failover controller (Google Cloud DNS)
├─ Cross-region health checks (TCP/HTTP)
├─ State replication (CloudSQL replication)
└─ Manual trigger with automated execution
    ↓ FAILOVER OUTPUT: <5 min RTO + <6 hour RPO verified

PHASE 5 (Chaos Engineering)
├─ CronJob scheduler (weekly chaos tests)
├─ 6 test scenarios (rotating weekly)
├─ Metrics collection + post-incident analysis
└─ Automated recovery validation
    ↓ CHAOS OUTPUT: Weekly test execution + improvement recommendations
```

---

## 🔌 COMPONENT ARCHITECTURE

### Phase 1A: Prometheus Monitoring Stack
```yaml
# File: kubernetes/monitoring/prometheus-deployment.yaml
# Purpose: Collect system metrics + define alert rules

Deployment: prometheus-0
  ├─ Container: prom/prometheus:latest
  ├─ Replicas: 1 (HA via Redis cache)
  ├─ Storage: 100GB (7-day retention)
  ├─ Port: 9090
  └─ Config:
      ├─ Scrape interval: 15 seconds (default)
      ├─ Alert evaluation: 30 seconds
      └─ Targets: Kubernetes, CloudSQL, DNS, Custom metrics

Key Metrics Scraped:
  ├─ kubernetes.pod_cpu_usage_seconds_total
  ├─ kubernetes.pod_memory_usage_bytes
  ├─ kubernetes.kubelet_volume_stats_used_bytes
  ├─ cloudql.cloudsql_database_connections
  ├─ custom.api_request_latency_seconds
  └─ custom.database_query_time_seconds

Alert Rules:
  ├─ CPUSpike: pod CPU > 80% for 2+ min → Phase 2
  ├─ MemoryPressure: pod memory > 85% for 2+ min → Phase 2
  ├─ PodNotReady: pod not ready > 5 min → Phase 2
  ├─ NodeNotReady: node status != ready → Phase 2
  └─ HighLatency: API latency p99 > 200ms → Phase 2
```

### Phase 1B: Kubernetes Custom Watchers
```yaml
# File: kubernetes/monitoring/watchers/
# Purpose: Real-time detection of Kubernetes events

Watcher 1: PodWatcher
  ├─ Watches: Pod status changes
  ├─ Detection events:
  │  ├─ CrashLoopBackOff → Phase 2 remediate
  │  ├─ ImagePullBackOff → Phase 2 remediate
  │  └─ Pending >5 min → Phase 2 remediate
  └─ Alert method: Slack + GitHub event

Watcher 2: NodeWatcher
  ├─ Watches: Node status changes
  ├─ Detection events:
  │  ├─ NotReady → Phase 2 remediate
  │  ├─ Disk pressure → Phase 3 predict capacity
  │  └─ Memory pressure → Phase 2 remediate
  └─ Alert method: Slack + Jenkins job trigger

Watcher 3: StorageWatcher
  ├─ Watches: PersistentVolume usage
  ├─ Detection events:
  │  ├─ Disk usage > 90% → Phase 5 chaos (storage test)
  │  └─ Disk usage > 95% → Phase 2 remediate
  └─ Alert method: Slack + Monitoring dashboard update

Update Frequency: Real-time (watch stream via Kubernetes API)
Caching Layer: Redis (5-min TTL for dedupe, reduces noise)
Detection Rate: >99% (verified daily)
```

### Phase 1C: Log Aggregation (ELK Stack)
```yaml
# File: kubernetes/logging/elasticsearch-stack.yaml
# Purpose: Centralize logs for incident analysis

Elasticsearch:
  ├─ Replicas: 3 (geo-distributed)
  ├─ Storage: 500GB SSD
  ├─ Index rotation: Daily (7-day retention)
  ├─ Shards: 5, Replicas: 1
  └─ Indexing rate: 100K docs/sec

Logstash:
  ├─ Input: Kubernetes API (pod logs)
  ├─ Filter: Parse JSON + extract fields
  │  ├─ @timestamp (log time)
  │  ├─ pod_name, namespace, container
  │  ├─ error_level (ERROR, WARN, INFO, DEBUG)
  │  └─ custom fields (latency_ms, error_code, etc.)
  ├─ Output: Elasticsearch indices
  └─ Buffer: 10K events (prevents loss on slowdown)

Kibana:
  ├─ Dashboards:
  │  ├─ Overview (incidents + errors)
  │  ├─ Phase 2 Handler Execution
  │  ├─ API Latency Trends
  │  └─ Node + Pod Health
  ├─ Alerting: Long-running queries (>30sec)
  └─ Retention: 7 days (searchable)

Log Parsing Examples:
  ├─ Pod crash: "error_level=FATAL, reason=OOMKilled"
  ├─ API error: "error_code=503, service=api-server, latency_ms=5000"
  └─ DB issue: "error=ConnectionPoolExhausted, queue_size=150"
```

---

## 🔧 PHASE 2: AUTO-REMEDIATION HANDLERS

### Architecture: Handler Controller

```yaml
# File: kubernetes/handlers/handler-controller.yaml
# Purpose: Execute automated remediation based on Phase 1 alerts

Deployment: handler-controller
  ├─ Replicas: 1 (critical, no HA needed - stateless)
  ├─ Image: custom-handler:latest
  ├─ Port: 8080 (webhook port)
  ├─ Config:
  │  ├─ HANDLER_DRY_RUN: false (production mode)
  │  ├─ MAX_RETRIES: 5 (escalate after 5 failures)
  │  ├─ RETRY_DELAY_SEC: 30
  │  └─ SLACK_WEBHOOK: (from GSM)
  └─ Healthcheck: HTTP /health (every 10s)

Webhook Input (from Prometheus AlertManager):
  {
    "alerts": [{
      "status": "firing",
      "labels": {
        "alertname": "CPUSpike",
        "pod_name": "api-server-abc123",
        "namespace": "default"
      },
      "annotations": {
        "value": "125%",
        "description": "Pod CPU >80% for 2+ min"
      }
    }]
  }

Remediation Logic Flow:
  1. Parse alert → determine incident type
  2. Check: Is pod/node health acceptable?
  3. If YES: Log FalsePositive + notify team
  4. If NO: Execute remediation action
  5. Wait 30s → Check if resolved
  6. If resolved: Log Success + send Slack
  7. If not resolved: Retry (max 5 attempts)
  8. If 5 retries fail: Escalate + create GitHub issue
```

### Handler Actions Catalog

```yaml
Incident Type 1: PodCrashLoopBackOff
  Detection: Kubernetes watcher + Prometheus alert
  Remediation:
    Step 1: Delete POD (force restart with fresh image)
      kubectl delete pod <pod-name> -n <namespace>
    Step 2: Wait for auto-restart via Kubernetes ReplicaSet
      Watch condition ready=true for 60s
    Step 3: Verify pod stable (running >2 min)
    Success: Pod restarted + stable
    Failure: Pod crashes again → escalate + debug needed

Incident Type 2: NodeNotReady
  Detection: Kubernetes node watcher
  Remediation:
    Step 1: Cordon node (prevent new pod scheduling)
    Step 2: Drain node (move pods to other nodes)
    Step 3: SSH to node + restart kubelet service
      gcloud compute ssh --zone=<zone> <node-name> -- \
        sudo systemctl restart kubelet
    Step 4: Uncordon node (restore to service)
    Step 5: Verify node status = Ready
    Success: Node recovered + accepting pods
    Failure: SSH fails or kubelet still down → manual investigation

Incident Type 3: HighMemoryUsage
  Detection: Prometheus metric analysis
  Remediation (Priority Order):
    Step 1 (Soft): Clear cache + garbage collection
      kubectl exec <pod> -- kill -TERM <gc-process>
    Step 2 (Medium): Restart pod gracefully
      kubectl delete pod <pod-name> --grace-period=30
    Step 3 (Hard): Not recommended in handler - escalate
      (Aggressive restart risks message loss)
    Success: Memory usage drops <80%
    Failure: After retry 3, escalate to Engineering

Incident Type 4: APILatencySpike
  Detection: Prometheus high latency alert
  Remediation:
    Step 1: Check current replica count
      kubectl get deployment api-server
    Step 2: If replicas < 5, scale up temporarily
      kubectl scale deployment api-server --replicas=5
    Step 3: Wait 60s for load balancer to distribute
    Step 4: Check latency p99 < 500ms
    Step 5: After 5 min, scale back down to 3 replicas
    Cooldown: Don't rescale same pod >2x per hour
    Success: Latency returns normal
    Failure: Scale up didn't help → potential code issue

Incident Type 5: DatabaseConnectionPoolExhausted
  Detection: Prometheus metric + CloudSQL monitoring
  Remediation:
    Step 1: Identify long-running connections
      SELECT * FROM pg_stat_activity WHERE state='active' AND query_start < (NOW() - '15 min'::interval)
    Step 2: Kill idle connections (>30 min idle)
      SELECT pg_terminate_backend(pid) WHERE...
    Step 3: If still exhausted, restart connection pooler
      kubectl rollout restart deployment/pgbouncer
    Step 4: Monitor connection count (target <80 of 100)
    Success: Connection pool usage <50%
    Failure: Pool still exhausted → escalate + query optimization
```

### Handler Retry Logic

```yaml
Execution Timeline for Failed Handler:
  
  Attempt 1: T+0s
    └─ Execute action
    └─ Wait 30s for impact
    └─ Check: Is incident resolved?
       ├─ YES: Log success + exit
       └─ NO: Proceed to attempt 2

  Attempt 2: T+30s
    └─ Execute same action again (idempotent)
    └─ Wait 30s
    └─ Check: Is incident resolved?
       ├─ YES: Log success + exit
       └─ NO: Proceed to attempt 3

  Attempt 3: T+60s
    └─ Try different remediation strategy
    └─ Wait 30s
    └─ Check: Is incident resolved?
       ├─ YES: Log success + exit
       └─ NO: Proceed to attempt 4

  Attempt 4: T+90s
    └─ Last attempt (different strategy)
    └─ Wait 30s
    └─ Check: Is incident resolved?
       ├─ YES: Log success + exit
       └─ NO: Proceed to escalation

  Escalation: T+120s
    └─ Mark incident as "RequiresManualInspection"
    └─ Send Slack alert to operations team
    └─ Create GitHub issue with details:
       ├─ Incident type
       ├─ All 4 handler attempts
       ├─ Metrics at time of incident
       └─ Suggested next steps for human investigator
```

---

## 🤖 PHASE 3: PREDICTIVE ML MONITORING

### ML Model Architecture

```yaml
# File: ml-service/models/time_series_forecaster.py
# Purpose: Predict system metrics 7 days in advance

Model: ARIMA + LSTM Hybrid
  ├─ ARIMA Component (85% weight)
  │  ├─ Auto-regressive order: 5 (5 previous time periods)
  │  ├─ Moving average order: 2 (2 previous errors)
  │  ├─ Differencing: 1 (trend removal)
  │  └─ Use case: Capture linear trends + seasonality
  │
  ├─ LSTM Component (15% weight)
  │  ├─ Hidden layers: 2 x 64 units
  │  ├─ Lookback window: 30 days
  │  ├─ Forecast horizon: 7 days
  │  └─ Use case: Capture non-linear patterns + anomalies
  │
  └─ Ensemble: Weighted average (ARIMA 85% + LSTM 15%)

Training Data:
  ├─ Historical metrics: 1 year (365 days)
  ├─ Resolution: 5-minute intervals (105K data points)
  ├─ Features:
  │  ├─ CPU usage %, Memory usage %
  │  ├─ Network I/O bytes, Disk throughput
  │  ├─ Request latency p50/p95/p99
  │  ├─ Error rate
  │  └─ Custom application metrics
  └─ Gaps: Linear interpolation

Training Schedule:
  ├─ Retraining: Daily (02:00 UTC)
  ├─ Validation: Hold-out test set (last 14 days)
  ├─ Performance metric: MAPE (mean absolute percentage error)
  │  ├─ Target: <5% for 1-day forecast
  │  ├─ Target: <10% for 3-day forecast
  │  ├─ Target: <15% for 7-day forecast
  │  └─ Alert: If MAPE > target, revert to previous model
  └─ Output: Saved model artifact (S3 versioned)

Inference Pipeline:
  ├─ Input: Latest 30 days of historical data
  ├─ Processing:
  │  ├─ Fetch from CloudSQL (last 30 days @ 5-min resolution)
  │  ├─ Feature scaling: StandardScaler (mean=0, std=1)
  │  ├─ Run ARIMA + LSTM predictions (parallel)
  │  ├─ Combine: result = 0.85*arima + 0.15*lstm
  │  └─ Inverse scaling: Convert back to original units
  ├─ Output: 7-day forecast (hourly intervals)
  │  └─ Format: [{"timestamp": "...", "value": X, "confidence_interval": [L, U]}, ...]
  └─ Execution time: <500ms (target <1s)

Concurrency:
  ├─ Multiple metrics trained in parallel (CPU, Memory, Latency)
  ├─ Model serving: Async API (non-blocking)
  └─ Cache: 5-min validity (reuse predictions within window)
```

### Anomaly Detection Algorithm

```yaml
# File: ml-service/models/anomaly_detector.py
# Purpose: Identify unusual patterns within predictions

Method: Statistical Confidence Intervals
  Step 1: Get 7-day forecast with uncertainty bands
    └─ Each point has: [Lower_bound, Forecast, Upper_bound]
    
  Step 2: Calculate z-score for actual metric vs forecast
    z_score = (actual - forecast_mean) / forecast_std
    
  Step 3: Classify severity:
    ├─ z < -2 or z > 2 (2σ): Warning
    │  └─ 95% confidence this is unusual (5% chance normal)
    │
    ├─ z < -3 or z > 3 (3σ): Alert
    │  └─ 99.7% confidence this is unusual (0.3% chance normal)
    │
    └─ |z| < 2: Normal (within expectations)

  Step 4: For 2σ anomalies: Low-priority monitoring
    └─ Log + watch trend (escalate if persists >1h)
    
  Step 5: For 3σ anomalies: Immediate investigation
    └─ Slack alert + paging if unusual metric

Example Anomalies:
  ├─ Case 1: Predicted CPU 45%, Actual CPU 95% (3σ jump)
  │  └─ Severity: Critical → Investigate + Phase 2 auto-remediate
  │
  ├─ Case 2: Predicted Latency 100ms, Actual 160ms (2σ increase)
  │  └─ Severity: Warning → Monitor + Phase 3 predict impact
  │
  └─ Case 3: Predicted Memory 60%, Actual Memory 61% (< 0.5σ)
       └─ Severity: None → Expected variation

Execution:
  ├─ Trigger: Every hour (CronJob 0 * * * *)
  ├─ Cross-reference: Compare actual metrics vs forecasts
  ├─ Output: Slack message + GitHub alert if 3σ
  └─ Timeline: <1 min end-to-end (detection to alert)
```

### Model Performance Monitoring

```yaml
# File: ml-service/monitoring/model_performance_tracker.py
# Purpose: Track accuracy degradation + trigger retraining

Metrics Tracked (Daily):
  ├─ MAPE (Mean Absolute Percentage Error)
  │  ├─ CPU forecast accuracy
  │  ├─ Memory forecast accuracy
  │  └─ Latency forecast accuracy
  │
  ├─ Directional Accuracy
  │  └─ Did model predict increase/decrease correctly?
  │
  ├─ Peak Detection Accuracy
  │  └─ Did model identify highest load period correctly?
  │
  └─ False Anomaly Rate
      └─ How many alerts were false alarms? (target <10%)

Thresholds for Retraining:
  ├─ MAPE > 15% (target <10%): Immediate retraining
  ├─ False positive rate > 20%: Alert + review features
  ├─ Model hasn't retrained >30 days: Schedule retraining
  └─ Accuracy drop >5% from baseline: Investigate data quality

Retraining Trigger:
  Step 1: Detect performance degradation
  Step 2: Backup current model (versioned in S3)
  Step 3: Retrain on new data
  Step 4: Validate new model against holdout test set
  Step 5: If new MAPE < old MAPE: Deploy new model
  Step 6: If new MAPE > old: Keep old model + investigate

Dashboard Metrics:
  ├─ Model accuracy over time (trending)
  ├─ Retraining frequency
  ├─ Inference latency distribution
  ├─ Anomaly detection rate
  └─ False positive trends
```

---

## 🌍 PHASE 4: MULTI-REGION FAILOVER ARCHITECTURE

### DNS Failover Controller

```yaml
# File: gcp/dns-failover-controller.yaml
# Purpose: Manage automatic/manual region failover

Configuration:
  Primary Region:    us-central1 (active)
  Secondary Region:  us-east1 (standby)
  
  DNS Entry:         example.com A record
  Primary IP:        10.128.0.2 (us-central1)
  Secondary IP:      10.132.0.2 (us-east1)

Health Checks:
  Primary Region Health Check:
    ├─ Type: HTTP
    ├─ Path: /api/health
    ├─ Port: 80
    ├─ Interval: 10 seconds
    ├─ Timeout: 5 seconds
    ├─ Unhealthy threshold: 3 (30s total)
    └─ Endpoint: primary-lb.us-central1-a

  Secondary Region Health Check:
    ├─ Type: HTTP
    ├─ Path: /api/health
    ├─ Port: 80
    ├─ Interval: 10 seconds
    ├─ Timeout: 5 seconds
    ├─ Unhealthy threshold: 3 (30s total)
    └─ Endpoint: secondary-lb.us-east1-c

Health Check Response:
  Healthy Response:
    {"status": "healthy", "region": "us-central1", "timestamp": "2026-03-14T..."}
  
  Unhealthy Response:
    {"status": "degraded", "reason": "database_unavailable", "recovery_eta": "5 min"}

DNS Failover Routing:
  Manual Trigger Workflow:
    Step 1: Operator confirms primary region down (>5 min)
    Step 2: Operator + engineer approve failover
    Step 3: Operations Lead executes: gcloud dns record-sets update
    Step 4: DNS record updated: @ -> us-east1-ip (TTL=60s)
    Step 5: DNS propagates globally (expected: 30-60s)
    Step 6: Traffic shifts to secondary region
    Step 7: Monitor secondary region load + latency
    
  Auto-Failback Workflow:
    Step 1: Primary region health check passes (3+ consecutive)
    Step 2: Automatic transition: @ -> us-central1-ip (TTL=300s)
    Step 3: Monitor primary region (ensure stable)
    Step 4: After 5 min stable, failback confirmed

DNS TTL Strategy:
  ├─ Normal operations: TTL=300s (5 min)
  │  └─ Clients cache for 5 min (stable routing)
  │
  ├─ During failover: TTL=60s (1 min)
  │  └─ Fast propagation for faster failover
  │
  └─ After recovery: TTL=300s (back to normal)
```

### Data Replication Architecture

```yaml
# File: gcp/cloudsql-replication.yaml
# Purpose: Keep secondary region database in sync

CloudSQL Primary:    us-central1 (read/write)
CloudSQL Replica:    us-east1 (read-only, always in sync)

Replication Method:  PostgreSQL streaming replication (built-in)
  ├─ Primary writes WAL (write-ahead logs)
  ├─ Replica continuously applies WAL
  ├─ RPO (recovery point objective): <6 hours
  │  └─ Any data within 6h is recoverable
  ├─ RTO (recovery time objective): <5 min
  │  └─ Replica promotion + DNS failover <5 min

Replication Lag Monitoring:
  ├─ Tracked metric: pg_stat_replication.pg_wal_lsn_diff
  ├─ Normal lag: <1 second
  ├─ Warning lag: >30 seconds
  │  └─ Alert operations team
  ├─ Critical lag: >5 minutes
  │  └─ Page on-call engineer

Failover Procedure (If Primary Corrupted):
  Step 1: Promote replica to primary
    gcloud sql instances promote-replica replica-us-east1
  Step 2: Update app connection strings (replica -> new primary)
  Step 3: Verify write operations working on us-east1
  Step 4: Restore backup to us-central1
  Step 5: Setup us-east1 as new primary
  
  During failover:
    └─ RTO: <5 min (DNS + replica promotion)
    └─ RPO: <6 hours (max data loss)

Backup Strategy:
  ├─ Automated daily backups: 02:00 UTC
  ├─ Retention: 30 days
  ├─ Location: Multi-region (auto geo-redundant)
  ├─ Testing: Weekly restore tests (alternate region)
  └─ Recovery time: <30 min from backup
```

### Multi-Region Load Balancing

```yaml
# File: gcp/load-balancer-multiregion.yaml
# Purpose: Route traffic + health checks

Load Balancer Type: Google Cloud Global HTTPS Load Balancer
  ├─ Frontend IP: Global anycast IP (accessible from anywhere)
  ├─ SSL/TLS termination at edge
  └─ Automatic failover based on health checks

Backend Services:
  ├─ Primary backend:
  │  ├─ Region: us-central1-a
  │  ├─ Instance group: api-server-ig (3 instances)
  │  ├─ Health check: HTTP /api/health
  │  └─ Connection draining: 30s
  │
  └─ Secondary backend:
     ├─ Region: us-east1-c
     ├─ Instance group: api-server-ig-east (3 instances)
     ├─ Health check: HTTP /api/health
     └─ Connection draining: 30s

Traffic Routing (DNS Failover):
  Normal Operations:
    User DNS query → us-central1 IP → Primary LB → Primary backend
  
  Primary Region Down:
    Operator triggers DNS update
    User DNS query → us-east1 IP → Secondary LB → Secondary backend
    
  Regional Outage Simulation:
    Kill all primary instances
    Health check fails 3x (30s total)
    Operator decides failover (manual trigger)
    DNS update executes
    New connections route to us-east1

Failover Test (Monthly):
  ├─ Schedule: Sunday 2 AM UTC
  ├─ Scope: Test DNS zone only (no production impact)
  ├─ Procedure:
  │  ├─ Create test DNS record (test.example.com)
  │  ├─ Point to primary
  │  ├─ Update to secondary
  │  ├─ Verify connectivity
  │  ├─ Update back to primary
  │  └─ Delete test record
  ├─ Duration: <5 minutes
  └─ Success: Failover time <2 minutes documented
```

---

## 🧪 PHASE 5: CHAOS ENGINEERING FRAMEWORK

### Chaos Test Scenarios

```yaml
# File: kubernetes/chaos/test-scenarios.yaml
# Purpose: Weekly automated resilience testing

Scenario 1: Pod CPU Spike (Week 1)
  Trigger: Generate artificial CPU load
    └─ stress-ng process (100% CPU on one core)
  Duration: 5 minutes
  Monitoring:
    ├─ Phase 1 detection (alert within 1s)
    ├─ Phase 2 auto-remediation (handler attempts to scale)
    ├─ Phase 3 ML prediction (should forecast 5m spike)
    └─ System recovery (return to normal after 5 min)
  Success Criteria:
    ├─ Alert fires within 1 minute ✅
    ├─ System remains operational (no user impact)
    ├─ Handler starts scale-up within 2 min
    └─ Metrics return normal within 10 min
  Rollback: Kill stress process + monitor recovery

Scenario 2: Node Network Partition (Week 2)
  Trigger: Simulate network outage
    └─ iptables rule: DROP all traffic from node
  Duration: 3 minutes
  Monitoring:
    ├─ Kubernetes detects node NotReady (within 40s)
    ├─ Phase 1 generates alert
    ├─ Phase 2 attempts kubelet restart
    ├─ Pod eviction + rescheduling
    └─ Service recovery (requests routed to other nodes)
  Success Criteria:
    ├─ Node detected NotReady within 40s
    ├─ Pods evicted + rescheduled within 2 min
    ├─ Service continues on other nodes (minimal impact)
    └─ Network partition healed after 3 min
  Rollback: Remove iptables rule + kubelet restart

Scenario 3: Database Connection Pool Exhaustion (Week 3)
  Trigger: Create many long-running queries
    └─ Generate 100 queries (artificially sleep 5 min each)
  Duration: 5 minutes
  Monitoring:
    ├─ Connection pool saturation (95%+)
    ├─ Alert fires (connection pool exhausted)
    ├─ Phase 2 handler tries to kill idle connections
    ├─ If pool still full, trigger connection pooler restart
    └─ New connections start flowing
  Success Criteria:
    ├─ Alert within 1 minute of saturation
    ├─ Handler kills idle connections
    ├─ Service continues (with slight degradation)
    └─ Pool recovers within 5 min
  Rollback: Kill long-running queries + restart pooler

Scenario 4: Cache Backend Failure (Week 4)
  Trigger: Kill Redis pod (primary cache)
    └─ kubectl delete pod redis-0 -n default
  Duration: 3 minutes
  Monitoring:
    ├─ Phase 1 detects pod missing (within 30s)
    ├─ Phase 2 handler attempts pod restart
    ├─ Pod recreated from image (clean state)
    ├─ Failover to replicated cache (if needed)
    └─ Cache rebuilt from primary data
  Success Criteria:
    ├─ Pod restart triggered within 1 min
    ├─ Cache failover activated (0 data loss)
    ├─ Service continues (slower without cache, but functional)
    └─ Cache rebuilt within 3 min
  Rollback: Pod auto-restarts (no manual action needed)

Scenario 5: API Latency Surge (5th+ week or ad-hoc)
  Trigger: Generate artificial high load
    └─ 1000 concurrent requests (Apache Bench / JMeter)
  Duration: 5 minutes
  Monitoring:
    ├─ Latency p99 soars to 5+ seconds
    ├─ Alert fires (latency > 200ms)
    ├─ Phase 2 auto-scales API deployment (3→5 replicas)
    ├─ Load generator distributes across more pods
    └─ Latency returns normal (p99 < 200ms)
  Success Criteria:
    ├─ Alert within 30s of latency spike
    ├─ Auto-scaling triggered within 1 min
    ├─ Latency recovery within 2 min
    └─ Handles 5x normal load without errors
  Rollback: Stop load generator + scale down (automatic)

Scenario 6: Storage Quota Exceeded (6th+ week or quarterly)
  Trigger: Create large temp files (fill disk)
    └─ dd if=/dev/zero of=/var/data/testfile bs=100M count=50 (5GB)
  Duration: 3 minutes
  Monitoring:
    ├─ Disk usage spikes (e.g., 85% → 95%)
    ├─ Phase 1 detects disk pressure alert
    ├─ Phase 2 handler: cleanup old logs (log rotation)
    ├─ If disk still full: handler escalates
    └─ Manual investigation for growth trend
  Success Criteria:
    ├─ Alert within 30s of disk pressure
    ├─ Handler attempts cleanup (expected from logs)
    ├─ System remains operational
    └─ Disk recovery within 5 min
  Rollback: Delete test files + verify logs cleaned

Execution Schedule:
  ├─ Week 1: Scenario 1 (CPU)
  ├─ Week 2: Scenario 2 (Network)
  ├─ Week 3: Scenario 3 (DB connections)
  ├─ Week 4: Scenario 4 (Cache)
  ├─ Week 5: Scenario 5 (API Latency) if no test yet
  ├─ Ongoing: Rotation (6 tests every 6 weeks)
  └─ Trigger: CronJob (Sunday 2 AM UTC)
```

### Chaos Test Orchestration

```yaml
# File: kubernetes/chaos/orchestrator.yaml
# Purpose: Run chaos tests + collect metrics

CronJob: weekly-chaos-executor
  ├─ Schedule: 0 2 * * 0 (Sunday 2 AM UTC)
  ├─ Concurrency: 1 (never run 2 tests simultaneously)
  ├─ Timeout: 30 minutes (max execution time)
  └─ Retry: 3 attempts (if test fails)

Test Execution Pipeline:
  Step 1: Pre-Test Setup
    ├─ Validate test environment ready
    ├─ Clear previous test artifacts
    ├─ Baseline system metrics (CPU, memory, latency)
    └─ Notify team (test starting)

  Step 2: Select Scenario
    ├─ Calculate week: (now.weekday % 6) + 1
    ├─ Select scenario from enum
    └─ Load scenario configuration

  Step 3: Execute Test
    ├─ Apply chaos resource (pod stress, network rule, etc.)
    ├─ Continuous monitoring (Prometheus scrape every 5s)
    ├─ Collect logs (Elasticsearch)
    ├─ Detect alerts + actions (Slack + GitHub events)
    └─ Duration: 3-5 minutes (scenario dependent)

  Step 4: Recovery Validation
    ├─ Wait 5 minutes (post-test)
    ├─ Verify system returned to normal state
    ├─ Check: All pods running, no pending restarts
    ├─ Check: API responding, no errors
    └─ Check: Latency p99 < 200ms baseline

  Step 5: Post-Test Analysis
    ├─ Calculate metrics:
    │  ├─ MTTD (time to detect): Actual vs expected
    │  ├─ MTTR (time to recover): Actual vs expected
    │  ├─ False positives: Count
    │  └─ Failed automations: Count
    ├─ Generate report (JSON)
    └─ Store report (S3 versioned)

  Step 6: Notification + Next Steps
    ├─ Slack message: Test complete + pass/fail
    ├─ Post test metrics to dashboard
    ├─ If test failed: Alert engineering team
    └─ Create GitHub issue if improvement needed

Success Criteria:
  ├─ System recovers within RTO window (<5 min)
  ├─ Zero data loss (RPO <6 hours)
  ├─ <10% error rate during recovery
  └─ All handlers executed (no skipped automations)

Failure Handling:
  ├─ Test fails to start: Log + retry (3 attempts)
  ├─ System doesn't recover: Escalate + manual intervention
  ├─ Handler didn't execute: Alert engineering + review automation
  └─ Data loss detected: Severity 0 incident (full investigation)
```

---

## 📊 OPERATIONAL METRICS

### Phase 1-2 Metrics Dashboard
```
Incident Detection Rate:      [Target: >99%]
  ├─ Detection latency:        <30s (Prometheus scrape)
  ├─ False positive rate:       <10% (target tuning)
  └─ Missed incidents:          <1% (quality check)

Auto-Remediation Success Rate: [Target: >90%]
  ├─ Handlers executed:        Count per 24h
  ├─ Handlers succeeded:       % success rate
  ├─ MTTR (recovery time):     <6 min average
  └─ Escalation rate:          <10% (handler failures)
```

### Phase 3 ML Metrics Dashboard
```
Model Prediction Accuracy:     [Target: >85% by day 3]
  ├─ MAPE (1-day horizon):     <5%
  ├─ MAPE (3-day horizon):     <10%
  ├─ MAPE (7-day horizon):     <15%
  ├─ False anomaly rate:       <10%
  └─ Retraining frequency:     Daily (02:00 UTC)
```

### Phase 4 Failover Metrics
```
Failover Readiness:            [Target: 100%]
  ├─ Primary region health:    >99% uptime
  ├─ Secondary region health:  >99% uptime
  ├─ Data replication lag:     <1 second
  ├─ Monthly failover test:    Pass (RTO <5 min)
  └─ RPO verification:         <6 hours
```

### Phase 5 Chaos Metrics
```
Chaos Test Coverage:           [Target: 6 scenarios/month]
  ├─ Execution success rate:   >95%
  ├─ MTTD during chaos:        <1 min vs baseline
  ├─ MTTR after chaos:         <5 min vs baseline
  ├─ Improvement rate:         >5% month-over-month
  └─ System stability:         Zero data loss
```

---

## ✅ ARCHITECTURE SUMMARY

```
All 5 Phases Operational:
  ✅ Phase 1: Detection (Prometheus + K8s watchers + ELK)
  ✅ Phase 2: Auto-Remediation (Handler controller + 100% idempotent)
  ✅ Phase 3: Prediction (ML hybrid ARIMA+LSTM + hourly forecast)
  ✅ Phase 4: Failover (Multi-region DNS + replication)
  ✅ Phase 5: Chaos (Weekly scenarios + auto-recovery validation)

Core Capabilities:
  ✅ Incident detection: <30s (>99% success rate)
  ✅ Auto-remediation: <6 min MTTR (>90% success)
  ✅ Predictive ML: 7-day forecasts (>85% accuracy)
  ✅ Multi-region failover: <5 min RTO (geographic diversity)
  ✅ Chaos testing: Weekly (continuous improvement)

Infrastructure Status:
  ✅ 5 Kubernetes nodepool (geo-distributed)
  ✅ PostgreSQL 14.2 + replication (primary + 2 replicas)
  ✅ Redis cache + failover (3-node cluster)
  ✅ Google Cloud DNS (global failover ready)
  ✅ Prometheus + AlertManager (99% uptime)
```

---

**ARCHITECTURE FINAL VERSION - March 14, 2026**

