Instrumentation examples

Python (Flask) using `prometheus_client`:

```py
from prometheus_client import Counter, Histogram, generate_latest
from prometheus_client import start_http_server

REQUESTS = Counter('canonical_secrets_api_requests_total', 'Total requests', ['method','path','status'])
LATENCY = Histogram('canonical_secrets_api_response_time_ms', 'Response time ms', buckets=[50,100,200,500,1000,2000])

def handle_request(req):
    with LATENCY.time():
        # process
        status = 200
        REQUESTS.labels(method='POST', path='/v1/rotate', status=str(status)).inc()
        return 'ok', status

if __name__ == '__main__':
    start_http_server(8000)  # metrics endpoint

    # integrate into your web framework to expose /metrics
```

Go (net/http) using `prometheus/client_golang` snippet:

```go
var (
    reqs = prometheus.NewCounterVec(
        prometheus.CounterOpts{ Name: "canonical_secrets_api_requests_total", Help: "Total requests" },
        []string{"method","path","status"},
    )
)

func main() {
    prometheus.MustRegister(reqs)
    http.Handle("/metrics", promhttp.Handler())
    http.ListenAndServe(":8000", nil)
}
```

Notes:
- Expose `/metrics` on a dedicated port and ensure ServiceMonitor or scrape config targets it.
- Include `status` label to compute success rates for SLOs.
