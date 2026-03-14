# SSO Platform - TIER 2: Observability & Performance

## Overview

TIER 2 provides comprehensive observability through distributed tracing, metrics collection, and pre-configured dashboards. This enables rapid incident response, capacity planning, and SLO compliance verification.

## Components

### 1. Grafana Tempo (Distributed Tracing)

**File**: `infrastructure/sso/monitoring/tempo-tracing.yaml`

#### What It Does
- Captures complete request traces across services
- Stores traces in GCS bucket (cost-optimized)
- Provides Grafana UI for trace visualization
- Enables root cause analysis for errors

#### Architecture
```
Applications (OTLP instrumentation)
    ↓
Tempo Receiver (gRPC :4317, HTTP :4318)
    ↓
Tempo ServiceMemory (buffering + batching)
    ↓
GCS Storage (scalable, long-term)
    ↓
Grafana Explore UI (trace search & visualization)
```

#### Key Traces Captured
- OAuth2 authorization flow (client → OAuth2-Proxy → Keycloak → DB)
- Token validation (API Gateway → OAuth2-Proxy)
- Database queries (Keycloak → PostgreSQL)
- Cache hits/misses (Redis operations)

#### Deployment
```bash
kubectl apply -f infrastructure/sso/monitoring/tempo-tracing.yaml
kubectl get deployment -n keycloak tempo
kubectl logs -n keycloak -l app=tempo --tail=50
```

#### Query Traces
```bash
# Port-forward Grafana
kubectl port-forward -n keycloak svc/grafana 3000:80 &

# Open https://localhost:3000 → Explore → Select Tempo data source
# Query examples:
#   - Service: keycloak (all Keycloak traces)
#   - Operation: POST /realms/master/protocol/openid-connect/token
#   - Status: error (only failed requests)
#   - Duration: > 1s (slow requests)
```

#### Instrumentation
```javascript
// JavaScript client auto-instrumentation
import { BasicTracerProvider } from '@opentelemetry/sdk-trace-web';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';

const provider = new BasicTracerProvider();
const exporter = new OTLPTraceExporter({
  url: 'http://tempo:4318/v1/traces',
});
provider.addSpanProcessor(new SimpleSpanProcessor(exporter));
setGlobalTracerProvider(provider);
```

### 2. Grafana Dashboards (Pre-configured)

**File**: `infrastructure/sso/monitoring/grafana-dashboards.yaml`

#### What It Does
- Provides 10 pre-built dashboards
- Real-time visualization of all key metrics
- Instant status overview for SRE/Ops teams
- Click-through to detail pages

#### Dashboard List

| Dashboard | Metrics | Update Interval | Purpose |
|-----------|---------|-----------------|---------|
| **Keycloak Status** | Active users, token generation rate, auth success/fail | 5s | Identity provider health |
| **OAuth2-Proxy** | Request rate, latency, auth denials | 5s | Gateway health |
| **PostgreSQL** | Query latency, connection count, replication lag | 10s | Database performance |
| **Redis Cache** | Hit rate, memory usage, evictions | 10s | Cache efficiency |
| **Kubernetes Resources** | CPU, memory, disk I/O | 30s | Node utilization |
| **Network Flows** | In/out bandwidth, packet loss | 30s | Network health |
| **Security Events** | Auth failures, policy violations | 5s | Anomaly detection |
| **SLO Progress** | Availability %, latency p99, error rate | 1m | Compliance tracking |
| **Cost Analysis** | GCP resource consumption, billing | 1h | Budget tracking |
| **Audit Trail** | User actions, API calls, state changes | 1h | Compliance audit |

#### Access Dashboards
```bash
# Port-forward Grafana
kubectl port-forward -n keycloak svc/grafana 3000:80 &

# Open http://localhost:3000
# Login: admin / (password from secret)
# Dashboards tab → Select dashboard
```

#### Dashboard Customization
```bash
# Export dashboard JSON
kubectl get configmap -n keycloak grafana-dashboards \
  -o jsonpath='{.data.keycloak-status\.json}' > keycloak-status.json

# Modify and reimport
kubectl create configmap grafana-dashboards \
  --from-file=keycloak-status.json \
  -n keycloak --dry-run=client -o yaml | \
  kubectl apply -f -
```

### 3. Prometheus SLO Rules & Alerting

**File**: `infrastructure/sso/monitoring/prometheus-slo-rules.yaml`

#### What It Does
- Defines SLI (Service Level Indicators) as recording rules
- Calculates SLO compliance on a rolling basis
- Triggers alerts when SLOs are at risk
- Provides burndown visualization

#### SLO Targets
```yaml
✅ Availability:    99.9% (monthly error budget: 43 minutes)
✅ Latency (p99):   200ms (max response time 99% of requests)
✅ Error Rate:      0.1% (max 99.9% success rate)
✅ Cache Hit Rate:  85% (Redis efficiency target)
```

#### Recording Rules
```yaml
# Request rate (requests/second)
keycloak:request_rate_1m = rate(keycloak_http_requests_total[1m])

# Error rate (errors per request)
keycloak:error_rate_1m = rate(keycloak_http_requests_failed_total[1m])

# Availability (success ratio)
keycloak:availability_ratio = 1 - keycloak:error_rate_1m

# Latency (p99 percentile)
keycloak:latency_p99 = histogram_quantile(0.99, keycloak_http_request_duration_seconds)
```

#### Alert Rules
```yaml
KcKeyloakErrorRateHigh:
  - Threshold: error_rate > 0.5%
  - Severity: warning
  - Action: Page on-call if error_rate > 1%

KcKeycloakLatencyHigh:
  - Threshold: latency_p99 > 500ms
  - Severity: warning
  - Action: Check DB replication lag, cache hit rate

KcKeycloakSLOAtRisk:
  - Threshold: availability_ratio < 0.999
  - Severity: critical
  - Action: Immediate incident response
```

#### Query SLO Status
```bash
# Port-forward Prometheus
kubectl port-forward -n keycloak svc/prometheus 9090:90 &

# Open http://localhost:9090
# Query examples:
#   - keycloak:availability_ratio (current availability)
#   - topk(5, rate(keycloak_http_request_duration_seconds_bucket[5m]))
#   - increase(keycloak_http_requests_failed_total[1h])
```

### 4. Redis Cache Layer

**File**: `infrastructure/sso/11-redis-cache-layer.yaml`

#### What It Does
- Caches OAuth2 tokens & user sessions
- 3-node HA cluster with automatic failover
- Data persistence to GCS
- Memory optimization (LRU eviction)

#### Architecture
```
Application Cache Requests
        ↓
Redis Cluster (3 nodes)
├── Master (writes)
├── Replica 1 (high availability)
└── Replica 2 (high availability)
        ↓
GCS Snapshot (persistence)
```

#### Cache Keys
```
oauth2:tokens:{client_id}:{subject}        → Access tokens (TTL: 1h)
oauth2:sessions:{session_id}               → Session data (TTL: 24h)
keycloak:users:{user_id}                   → User cache (TTL: 5m)
keycloak:roles:{realm}:{user_id}           → Role membership (TTL: 10m)
```

#### Configuration
```yaml
# Redis Helm Values
redis:
  persistence:
    enabled: true
    size: 10Gi
  replicas: 3
  resources:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 512Mi
      cpu: 500m
```

#### Monitoring Redis
```bash
# Connect to Redis cluster
kubectl run -it --rm redis-cli --image=redis --restart=Never \
  -n keycloak -- \
  redis-cli -h redis-cluster.keycloak.svc.cluster.local -p 6379

# Check cluster status
> CLUSTER INFO
> CLUSTER NODES

# Monitor memory usage
> INFO memory

# Check key expiration
> MONITOR
```

### 5. PgBouncer Connection Pooling

**File**: `infrastructure/sso/12-pgbouncer-pooling.yaml`

#### What It Does
- Pools PostgreSQL connections (1000 max)
- Reduces connection overhead
- Implements transaction-level pooling
- Enables precise connection accounting

#### Connection Pool Configuration
```yaml
pgbouncer:
  pool_mode: transaction        # New connection per transaction
  max_client_conn: 1000         # Max client connections
  default_pool_size: 25         # Connections per server
  reserve_pool_size: 5          # Standby connections
  reserve_pool_timeout: 3s      # Timeout for reserve connections
```

#### Monitoring Connection Pool
```bash
# Connect to PgBouncer admin
kubectl run -it --rm psql --image=postgres --restart=Never \
  -n keycloak -- \
  PGPASSWORD=$(kubectl get secret pgbouncer -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -h pgbouncer -U pgbouncer -d pgbouncer -p 6432

# Show pools
> SHOW POOLS;

# Show clients
> SHOW CLIENTS;

# Show server connections
> SHOW SERVERS;
```

#### Performance Tuning
```sql
-- Increase pool size if connection saturation > 90%
UPDATE pgbouncer.config SET default_pool_size = 50 WHERE pool = 'keycloak';

-- Disable connection pooling for specific queries if needed
SHOW settings WHERE name = 'pool_mode';
UPDATE pgbouncer.config SET pool_mode = 'session' WHERE pool = 'keycloak-batch';
```

## Deployment Sequence

### Phase 1: Deploy Observability Stack (5 min)
```bash
# Tracing infrastructure
kubectl apply -f infrastructure/sso/monitoring/tempo-tracing.yaml

# SLO rules
kubectl apply -f infrastructure/sso/monitoring/prometheus-slo-rules.yaml

# Dashboards (Grafana will auto-import)
kubectl apply -f infrastructure/sso/monitoring/grafana-dashboards.yaml

# Caching layer
kubectl apply -f infrastructure/sso/11-redis-cache-layer.yaml

# Connection pooling
kubectl apply -f infrastructure/sso/12-pgbouncer-pooling.yaml
```

### Phase 2: Verify Deployments (3 min)
```bash
# Check all components are running
kubectl get deployment,statefulset -n keycloak

# Verify Prometheus scrape targets
kubectl port-forward -n keycloak svc/prometheus 9090:90 &
# Open http://localhost:9090/targets → Check all green

# Verify Grafana dashboards loaded
kubectl port-forward -n keycloak svc/grafana 3000:80 &
# Open http://localhost:3000 → Dashboards tab
```

### Phase 3: Configure Alerting (2 min)
```bash
# Update alert routing (add your Slack/PagerDuty webhook)
kubectl edit configmap alertmanager -n keycloak

# Reload Prometheus config
kubectl rollout restart deployment prometheus -n keycloak
```

## Key Metrics & Queries

### Request Performance
```promql
# Request rate (requests/second)
rate(keycloak_http_requests_total[5m])

# 99th percentile latency
histogram_quantile(0.99, rate(keycloak_http_request_duration_seconds_bucket[5m]))

# Error rate
rate(keycloak_http_requests_failed_total[5m])
```

### Database Performance
```promql
# Query latency
rate(pg_stat_statements_mean_time{db='keycloak'}[5m])

# Connection count
pg_stat_activity_count{state='active'}

# Replication lag
pg_replication_lag_seconds
```

### Cache Performance
```promql
# Cache hit rate
rate(redis_keyspace_hits_total[5m]) / 
  (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))

# Memory usage
redis_memory_used_bytes / redis_memory_max_bytes
```

## Advanced Observability

### Trace Sampling
```yaml
# Sample 10% of traces for cost savings
traceSamplerConfig:
  samplingPercentage: 10
  # High-priority traces always sampled:
  alwaysSample:
    - endpoint: "/login"
    - errorStatus: "5*"
```

### Custom Metrics
```bash
# Export custom metric from application
import { Counter } from '@opentelemetry/api-metrics';

const loginCounter = meter.createCounter('custom_sso_logins', {
  description: 'Count of successful logins',
});

loginCounter.add(1, { provider: 'google' });
```

### SLO Tracking Dashboard
```grafana
// SQL query to track SLO burndown
SELECT
  time,
  100 * (1 - error_rate) as slo_attainment,
  CASE
    WHEN error_rate > 0.001 THEN 'At Risk'
    WHEN error_rate > 0.0001 THEN 'Good'
    ELSE 'Excellent'
  END as slo_status
FROM
  prometheus_metrics
WHERE
  metric = 'keycloak:error_rate_1m'
ORDER BY time DESC
LIMIT 2880
```

## Troubleshooting

### Traces Not Appearing in Grafana
```bash
# Check Tempo is receiving traces
kubectl logs -n keycloak -l app=tempo --tail=100 | grep -i trace

# Verify applications are exporting traces
kubectl logs -n keycloak -l app=keycloak --tail=50 | grep -i otlp

# Check network connectivity to Tempo
kubectl run -it --rm debug --image=busybox --restart=Never -n keycloak -- \
  wget -O- http://tempo:4318/v1/traces
```

### Alerts Not Firing
```bash
# Check AlertManager configuration
kubectl get configmap alertmanager -n keycloak -o yaml

# Verify alert rules are loaded
kubectl exec -it prometheus-0 -n keycloak -- \
  curl localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name | contains("slo"))'

# Test alert webhook
curl -X POST http://localhost:9093/api/v1/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels": {"alertname": "TestAlert", "severity": "critical"}}]'
```

### Cache Hit Rate Low (<80%)
```bash
# Check Redis memory pressure
kubectl exec -it redis-cluster-0 -n keycloak -- redis-cli INFO | grep used_memory

# Increase cache TTLs
kubectl edit configmap keycloak-env -n keycloak
# Update KEYCLOAK_CACHE_SESSION_TTL=3600 (seconds)

# Monitor eviction policy
kubectl exec -it redis-cluster-0 -n keycloak -- redis-cli CONFIG GET maxmemory-policy
```

## Next Steps

After TIER 2 is deployed:
1. Review all 10 dashboards in Grafana
2. Establish alert thresholds with team
3. Configure escalation policies (on-call rotation)
4. Proceed to TIER 3: Compliance & Auditing

---

**Last Updated**: 2026-03-14
**Version**: 1.0.0
**Status**: Production Ready
