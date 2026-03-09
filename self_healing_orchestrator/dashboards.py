"""Prometheus and Grafana dashboard templates."""
import json
from typing import Dict, Any


def get_prometheus_rules() -> str:
    """Return Prometheus alert rules in YAML format."""
    return """
groups:
  - name: self-healing-orchestrator
    interval: 30s
    rules:
      # High failure rate for a module
      - alert: RemediationHighFailureRate
        expr: |
          (rate(remediation_attempts_total{status="failed"}[5m]) / rate(remediation_attempts_total[5m])) > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High remediation failure rate for {{ $labels.module }}"
          description: "{{ $labels.module }} has >50% failure rate over last 5m"

      # Deployment failure
      - alert: DeploymentFailed
        expr: increase(deployments_total{status="failed"}[1h]) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Deployment failed in {{ $labels.environment }}"
          description: "A deployment has failed in {{ $labels.environment }} environment"

      # Too many gaps detected
      - alert: TooManyGapsDetected
        expr: increase(gaps_detected_total{severity="critical"}[1h]) > 5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Too many critical gaps detected"
          description: "{{ $value | humanize }} critical gaps detected in last hour"

      # Health check failing
      - alert: HealthCheckFailing
        expr: rate(health_checks_total{result="failed"}[5m]) > 0.1
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Health check failing: {{ $labels.check_name }}"
          description: "Health check {{ $labels.check_name }} showing >10% failure rate"

      # Credential rotation failure
      - alert: CredentialRotationFailed
        expr: increase(credential_rotations_total{status="failed"}[1h]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Credential rotation failed for {{ $labels.provider }}"
          description: "Credential rotation failed for provider: {{ $labels.provider }}"
"""


def get_grafana_dashboard() -> Dict[str, Any]:
    """Return a Grafana dashboard JSON for the orchestrator."""
    return {
        "dashboard": {
            "title": "Self-Healing Orchestrator",
            "description": "Monitoring dashboard for self-healing orchestration framework",
            "tags": ["orchestrator", "self-healing", "ci-cd"],
            "timezone": "utc",
            "panels": [
                {
                    "title": "Remediation Success Rate",
                    "targets": [
                        {
                            "expr": "rate(remediation_attempts_total{status=\"success\"}[5m]) / rate(remediation_attempts_total[5m])"
                        }
                    ],
                    "type": "graph",
                },
                {
                    "title": "Deployment Frequency",
                    "targets": [
                        {
                            "expr": "rate(deployments_total[1h])"
                        }
                    ],
                    "type": "graph",
                },
                {
                    "title": "Active Deployments",
                    "targets": [
                        {
                            "expr": "active_deployments"
                        }
                    ],
                    "type": "gauge",
                },
                {
                    "title": "Gaps Detected (by severity)",
                    "targets": [
                        {
                            "expr": "increase(gaps_detected_total[1h])"
                        }
                    ],
                    "type": "bar",
                },
                {
                    "title": "Health Check Pass Rate",
                    "targets": [
                        {
                            "expr": "rate(health_checks_total{result=\"passed\"}[5m]) / rate(health_checks_total[5m])"
                        }
                    ],
                    "type": "percentage",
                },
                {
                    "title": "Credential Cache Hit Rate",
                    "targets": [
                        {
                            "expr": "rate(credential_cache_hits_total[5m]) / rate(credential_rotations_total[5m])"
                        }
                    ],
                    "type": "graph",
                },
            ],
        }
    }


__all__ = [
    "get_prometheus_rules",
    "get_grafana_dashboard",
]
