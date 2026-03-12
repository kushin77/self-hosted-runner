# Canonical Secrets Monitoring & Alerting Runbook

## Overview

This runbook documents how to operate the Canonical Secrets observability stack (Prometheus, Alertmanager, Grafana SLO dashboard).

---

## Alert: CanonicalSecretsAPIDown

**Severity:** CRITICAL

**Description:** API service is down for >2 minutes.

**Trigger:** `up{job="canonical-secrets-api"} == 0` for 2m

**Mitigation Steps:**
1. Check API pod status: `kubectl get pods -n canonical-secrets`
2. Review pod logs: `kubectl logs -n canonical-secrets -l app=canonical-secrets-api --tail=100`
3. Verify service connectivity from monitoring namespace: `kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://canonical-secrets-api:9090/health`
4. Review recent deployments/changes: `git log --oneline -n 10`
5. If recovery needed: `kubectl rollout restart deployment/canonical-secrets-api -n canonical-secrets`

**Recovery Time:** ~2 minutes for pod restart

---

## Alert: CanonicalSecretsHighErrorRate

**Severity:** WARNING

**Description:** >5% of API requests are returning 5xx errors.

**Trigger:** Error rate > 5% over 5m window

**Mitigation Steps:**
1. Query recent 5xx errors: `kubectl logs -n canonical-secrets -l app=canonical-secrets-api --since=5m | grep "5[0-9][0-9]"`
2. Check dependent services (Vault, GSM, backend): `kubectl get events -n canonical-secrets --sort-by='.lastTimestamp' | tail -20`
3. Review SLO dashboard: `kubectl port-forward -n monitoring svc/prometheus-kube-prom-grafana 3000:80`
4. If credential rotations are pending: check GSM/Vault for recent updates
5. Scale or restart if persistent: `kubectl scale deploy canonical-secrets-api --replicas=3 -n canonical-secrets`

---

## Alert: CanonicalSecretsHighLatencyP95

**Severity:** WARNING

**Description:** P95 latency exceeds 1000ms.

**Trigger:** P95 > 1000ms for 10m

**Mitigation Steps:**
1. Check resource utilization: `kubectl top pods -n canonical-secrets`
2. Review Prometheus query for slow endpoints: `histogram_quantile(0.95, rate(canonical_secrets_api_response_time_ms_bucket{handler=~"/.*"}[5m]))`
3. Identify slow operations: check audit logs for slow secret operations
4. If backend is slow, check database/Vault performance
5. Scale replicas if needed: `kubectl scale deploy canonical-secrets-api --replicas=5 -n canonical-secrets`

---

## Alert: ProviderFailoverDetected

**Severity:** INFO

**Description:** A failover between secret providers occurred (e.g., GSM → Vault).

**Trigger:** Failover count increased in 30m window

**Action Items:**
1. Log investigation: `kubectl logs -n canonical-secrets -l app=canonical-secrets-api --since=30m | grep -i failover`
2. Determine which provider failed: check GSM/Vault status
3. Note if it was expected (planned maintenance) or unexpected (outage)
4. Record in incident log for post-mortems

---

## Alert: SLOErrorBudgetBurnRateHigh

**Severity:** CRITICAL

**Description:** Error budget burn rate > 1 for 10 minutes (consuming full monthly SLO in 1 day).

**Trigger:** Burn rate > 1.0 for 10m

**Mitigation Steps:**
1. Immediately investigate CanonicalSecretsAPIDown and CanonicalSecretsHighErrorRate alerts
2. Check SLO dashboard for availability and error rates
3. If availability < 99%: trigger incident response
4. Implement faster recovery (restart, failover, scale)
5. Document root cause for post-incident review

---

## Alert: SLOAvailabilityBelowTarget

**Severity:** CRITICAL

**Description:** 7-day rolling availability below 99%.

**Trigger:** 7d availability < 0.99 for 30m

**Mitigation Steps:**
1. Review recent incidents and outages (last 7 days)
2. Check if incidents have been mitigated
3. Verify SLO calculation: `slo:availability:7d` in Prometheus
4. If newly triggered, escalate to team lead
5. Create incident postmortem and root-cause analysis

---

## Alert: SLOLatencyP95AboveTarget

**Severity:** WARNING

**Description:** 7-day rolling P95 latency exceeds 1000ms.

**Trigger:** 7d P95 > 1000ms for 30m

**Mitigation Steps:**
1. Identify slow endpoints: check Prometheus histogram buckets by endpoint
2. Correlate with provider failovers or API changes
3. If performance degradation recent: roll back or optimize
4. Review infrastructure metrics (CPU, memory, I/O)
5. Consider caching or request batching to reduce latency

---

## Health Checks

### Daily

```bash
# Check Prometheus is scraping metrics
kubectl port-forward -n monitoring svc/prometheus-kube-prom-prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/query?query=up{job="canonical-secrets-api"} | jq '.'

# Check Alertmanager has no firing alerts requiring action
curl -s http://localhost:9093/api/v2/alerts | jq '.[] | select(.status.state=="firing")'
```

### Weekly

- Review SLO dashboard: check 7d availability and P95
- Review error budget burn rate
- Verify Grafana dashboards are displaying correctly
- Check alert rules are up-to-date

---

## On-Call Handoff Checklist

- [ ] Alert fatigue assessment (silence non-actionable alerts)
- [ ] Verify Alertmanager is correctly routing notifications
- [ ] Test alert notifications (send test alert to on-call channel)
- [ ] Confirm runbook links are in alert annotations
- [ ] Verify incident response wiki or Slack channel is accessible
- [ ] Review recent incidents and any open postmortems

---

## References

- SLO Recording Rules: `monitoring/slo/slo_rules.yaml`
- Alert Rules: `monitoring/alert_rules/canonical_secrets_rules.yaml`
- SLO Dashboard: `monitoring/dashboards/slo_dashboard.json`
- Prometheus Helm Values: `monitoring/helm/prometheus-values.yaml`
- Deploy Script: `scripts/phase5_deploy_monitoring.sh`

---

**Last Updated:** 2026-03-12
