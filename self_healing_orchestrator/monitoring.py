"""Observability module for metrics, tracing, and alerting.

Provides instrumentation for the self-healing orchestration framework with:
- Prometheus metrics (counters, gauges, histograms)
- OpenTelemetry tracing support
- Health check metrics
- Deployment tracking and reporting
"""
import time
import logging
from typing import Optional, Dict, Any
from datetime import datetime
from enum import Enum

logger = logging.getLogger(__name__)

try:
    from prometheus_client import Counter, Gauge, Histogram, CollectorRegistry, generate_latest
    HAS_PROMETHEUS = True
except ImportError:
    HAS_PROMETHEUS = False

try:
    from opentelemetry import trace, metrics
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import SimpleSpanProcessor
    from opentelemetry.exporter.jaeger.thrift import JaegerExporter
    HAS_OTEL = True
except ImportError:
    HAS_OTEL = False


class MetricType(Enum):
    COUNTER = "counter"
    GAUGE = "gauge"
    HISTOGRAM = "histogram"


class MetricsCollector:
    """Collects metrics from the orchestration framework."""

    def __init__(self, registry: Optional[Any] = None):
        if HAS_PROMETHEUS:
            self.registry = registry or CollectorRegistry()
            
            # Remediation metrics
            self.remediation_attempts = Counter(
                "remediation_attempts_total",
                "Total remediation attempts",
                ["module", "status"],
                registry=self.registry
            )
            self.remediation_duration = Histogram(
                "remediation_duration_seconds",
                "Remediation duration in seconds",
                ["module"],
                registry=self.registry
            )
            
            # Orchestration metrics
            self.sequence_executions = Counter(
                "sequence_executions_total",
                "Total sequence executions",
                ["sequence", "status"],
                registry=self.registry
            )
            self.sequence_duration = Histogram(
                "sequence_duration_seconds",
                "Sequence execution duration",
                ["sequence"],
                registry=self.registry
            )
            
            # Health check metrics
            self.health_checks = Counter(
                "health_checks_total",
                "Total health checks",
                ["check_name", "result"],
                registry=self.registry
            )
            
            # Deployment metrics
            self.deployments = Counter(
                "deployments_total",
                "Total deployments",
                ["environment", "status"],
                registry=self.registry
            )
            self.active_deployments = Gauge(
                "active_deployments",
                "Active deployments",
                ["environment"],
                registry=self.registry
            )
            self.deployment_duration = Histogram(
                "deployment_duration_seconds",
                "Deployment duration",
                ["environment"],
                registry=self.registry
            )
            
            # Gap analysis metrics
            self.gaps_detected = Counter(
                "gaps_detected_total",
                "Total gaps detected",
                ["severity"],
                registry=self.registry
            )
            
            # Credential metrics
            self.credential_rotations = Counter(
                "credential_rotations_total",
                "Total credential rotations",
                ["provider", "status"],
                registry=self.registry
            )
            self.credential_cache_hits = Counter(
                "credential_cache_hits_total",
                "Credential cache hits",
                ["provider"],
                registry=self.registry
            )
        else:
            logger.warning("prometheus_client not installed; metrics disabled")

    def record_remediation_attempt(self, module: str, status: str, duration: float):
        if HAS_PROMETHEUS:
            self.remediation_attempts.labels(module=module, status=status).inc()
            self.remediation_duration.labels(module=module).observe(duration)

    def record_sequence_execution(self, sequence: str, status: str, duration: float):
        if HAS_PROMETHEUS:
            self.sequence_executions.labels(sequence=sequence, status=status).inc()
            self.sequence_duration.labels(sequence=sequence).observe(duration)

    def record_health_check(self, check_name: str, result: str):
        if HAS_PROMETHEUS:
            self.health_checks.labels(check_name=check_name, result=result).inc()

    def record_deployment(self, environment: str, status: str, duration: float):
        if HAS_PROMETHEUS:
            self.deployments.labels(environment=environment, status=status).inc()
            self.deployment_duration.labels(environment=environment).observe(duration)

    def record_gap(self, severity: str):
        if HAS_PROMETHEUS:
            self.gaps_detected.labels(severity=severity).inc()

    def record_credential_rotation(self, provider: str, status: str):
        if HAS_PROMETHEUS:
            self.credential_rotations.labels(provider=provider, status=status).inc()

    def record_credential_cache_hit(self, provider: str):
        if HAS_PROMETHEUS:
            self.credential_cache_hits.labels(provider=provider).inc()

    def metrics_as_bytes(self) -> bytes:
        """Export metrics in Prometheus format."""
        if HAS_PROMETHEUS:
            return generate_latest(self.registry)
        return b""


class TracingSetup:
    """Set up OpenTelemetry tracing."""

    def __init__(self, service_name: str = "self-healing-orchestrator",
                 jaeger_host: Optional[str] = None, jaeger_port: int = 6831):
        if HAS_OTEL:
            if jaeger_host:
                jaeger_exporter = JaegerExporter(
                    agent_host_name=jaeger_host,
                    agent_port=jaeger_port,
                )
                trace.set_tracer_provider(TracerProvider())
                trace.get_tracer_provider().add_span_processor(
                    SimpleSpanProcessor(jaeger_exporter)
                )
            self.tracer = trace.get_tracer(__name__)
        else:
            logger.warning("opentelemetry not installed; tracing disabled")
            self.tracer = None

    def start_span(self, name: str, attributes: Optional[Dict[str, Any]] = None):
        if self.tracer:
            span = self.tracer.start_span(name)
            if attributes:
                for k, v in attributes.items():
                    span.set_attribute(k, v)
            return span
        else:
            # Return a no-op context manager
            class NoOpSpan:
                def __enter__(self):
                    return self
                def __exit__(self, *args):
                    pass
            return NoOpSpan()


class DeploymentObserver:
    """Observes deployment events and records metrics."""

    def __init__(self, deployment_id: str, environment: str, 
                 metrics: Optional[MetricsCollector] = None,
                 tracing: Optional[TracingSetup] = None):
        self.deployment_id = deployment_id
        self.environment = environment
        self.metrics = metrics or MetricsCollector()
        self.tracing = tracing
        self.start_time = time.time()
        self.events: list[Dict[str, Any]] = []

    def record_event(self, event_type: str, details: Optional[Dict[str, Any]] = None):
        """Record an event for this deployment."""
        event = {
            "timestamp": datetime.utcnow().isoformat(),
            "type": event_type,
            "details": details or {},
        }
        self.events.append(event)
        logger.info("Deployment event [%s]: %s - %s", self.deployment_id, event_type, details)

    def record_sequence_completion(self, sequence_name: str, success: bool, duration: float):
        """Record completion of a remediation sequence."""
        status = "success" if success else "failed"
        self.record_event(f"sequence_{status}", {
            "sequence": sequence_name,
            "duration": duration,
        })
        self.metrics.record_sequence_execution(sequence_name, status, duration)

    def record_health_check_result(self, check_name: str, passed: bool):
        """Record health check result."""
        result = "passed" if passed else "failed"
        self.record_event(f"health_check_{result}", {"check": check_name})
        self.metrics.record_health_check(check_name, result)

    def record_gap_detected(self, gap_description: str, severity: str):
        """Record gap detection."""
        self.record_event("gap_detected", {
            "description": gap_description,
            "severity": severity,
        })
        self.metrics.record_gap(severity)

    def finalize(self, success: bool):
        """Mark deployment as complete."""
        duration = time.time() - self.start_time
        status = "success" if success else "failed"
        self.record_event(f"deployment_{status}", {"duration": duration})
        self.metrics.record_deployment(self.environment, status, duration)

    def get_events(self) -> list[Dict[str, Any]]:
        """Return all recorded events."""
        return self.events


__all__ = [
    "MetricsCollector",
    "TracingSetup",
    "DeploymentObserver",
]
