#!/usr/bin/env python3
"""
Simple Prometheus metrics server for milestone organizer.
Expose metrics for: assignments_total, assignment_failures_total, assignment_duration_seconds
Run alongside the organizer (Cloud Run sidecar or same container).
"""
from prometheus_client import start_http_server, Counter, Histogram
import time
import os

ASSIGNMENTS = Counter('milestone_assignments_total', 'Total milestone assignments', ['milestone'])
FAILURES = Counter('milestone_assignment_failures_total', 'Failed milestone assignments')
DURATION = Histogram('milestone_assignment_duration_seconds', 'Assignment duration seconds')

def simulate_metrics():
    # Placeholder: real integration should increment counters from assignment script
    while True:
        ASSIGNMENTS.labels(milestone='Secrets & Credential Management').inc(1)
        DURATION.observe(0.12)
        time.sleep(5)

if __name__ == '__main__':
    port = int(os.environ.get('METRICS_PORT', '8080'))
    start_http_server(port)
    print(f"Metrics server listening on :{port}")
    simulate_metrics()
