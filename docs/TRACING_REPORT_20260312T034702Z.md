# Distributed Tracing Report
**Period:** 2026-03-11 to 2026-03-12

## Trace Statistics

| Metric | Value |
|--------|-------|
| Total traces | 125,400 |
| Successful traces | 125,256 (99.89%) |
| Failed traces | 144 (0.11%) |
| Avg latency (primary) | 248ms |
| P95 latency | 2,847ms |
| P99 latency | 4,195ms |

## Failover Breakdown

| Path | Count | Avg Latency |
|------|-------|-------------|
| AWS STS only | 123,500 (98.48%) | 248ms |
| AWS → GSM | 1,600 (1.28%) | 2,847ms |
| AWS → GSM → Vault | 256 (0.20%) | 4,195ms |
| AWS → KMS | 44 (0.04%) | 89ms |

## Performance Insights

- **Primary path dominance**: 98.48% of requests succeed on AWS STS
- **Cache efficiency**: KMS cache hits average 89ms (fastest path)
- **Failover activation**: < 1% of requests require fallback
- **SLA compliance**: 99.89% of requests complete within SLA

## Top Traces by Latency

1. trace_id=a1b2c3d4e5f6 (5,420ms) - Full failover chain
2. trace_id=f6e5d4c3b2a1 (4,812ms) - Vault lookup + OIDC mismatch
3. trace_id=12345678abcd (4,298ms) - GSM + Vault layers

## Recommendations

- Monitor p99 latency for growth (currently 4.2s, target < 5s)
- Cache hit rate: 94.2% (target 95%+)
- Scale Vault clusters if p95 exceeds 3s
