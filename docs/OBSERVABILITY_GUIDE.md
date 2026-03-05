# Observability Guide

This document describes how to instrument services with Prometheus metrics and create Grafana dashboards.

## Prometheus Metrics

1. **Metric Naming**: use the `service_name_` prefix and follow [Prometheus naming conventions](https://prometheus.io/docs/practices/naming/).
2. **Basic Metrics**: counters for requests, histograms for latencies, gauges for current in-flight requests, and custom application metrics.
3. **Libraries**: use official client libraries (Node.js `prom-client`, Python `prometheus_client`, Go `prometheus`).
4. **Endpoint**: expose metrics at `/metrics` on a separate port or path keyed by service.

Example (Node.js):
```js
const client = require('prom-client');
const http = require('http');

const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics({ timeout: 5000 });

const requestCounter = new client.Counter({
  name: 'service_requests_total',
  help: 'Total requests received'
});

const server = http.createServer((req, res) => {
  if (req.url === '/metrics') {
    res.setHeader('Content-Type', client.register.contentType);
    res.end(client.register.metrics());
    return;
  }
  requestCounter.inc();
  res.end('hello world');
});

server.listen(3000);
```

## Grafana Dashboards

- Create a dashboard per service (template). Include panels:
  - Request rate (counter rate)
  - Latency histogram (bucket metrics)
  - Error count
  - System metrics (CPU, memory if available)
- Store dashboards as JSON under `docs/grafana/` to version control.

## Alerts

Set up Prometheus alert rules for:
- high error rates
- latency > SLO
- runner health check failures

---

## Security Hardening

### Dependency Scanning
The `security-scan.yml` workflow runs `npm audit` on each push/PR. Ensure vulnerabilities are triaged promptly.

### SBOM Generation
Use `./scripts/security/generate-sbom.sh` to produce an SBOM (`sbom.json`) for the repository. Store or publish it with your build artifacts.

### Signed Artifacts
When producing release artifacts (tarballs, binaries, container images), sign them using a GPG key or cosign. Example:

```sh
# sign a tarball
gpg --armor --output release.tar.gz.sig --detach-sign release.tar.gz
``` 

Add verification instructions to `docs/` and include public keys in your repo or a keyserver.

---

## Next Steps

- Add a `prometheus` scrape config in your deployment.
- Use `scripts/observability/generate-dashboard.sh` to create JSON templates.
