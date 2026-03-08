"""Tests for monitoring and alerting modules."""
from self_healing_orchestrator.monitoring import MetricsCollector, DeploymentObserver
from self_healing_orchestrator.alerts import AlertManager, AlertSeverity
from self_healing_orchestrator.dashboards import get_prometheus_rules, get_grafana_dashboard


def test_metrics_collector_basic():
    """Test basic metrics collection."""
    mc = MetricsCollector()
    
    # Record some metrics
    mc.record_remediation_attempt("test-module", "success", 0.5)
    mc.record_sequence_execution("test-seq", "success", 1.2)
    mc.record_health_check("test-check", "passed")
    mc.record_deployment("production", "success", 5.0)
    
    # Export metrics (should not crash)
    metrics = mc.metrics_as_bytes()
    assert b"remediation_attempts_total" in metrics or metrics == b""  # Depends on whether prometheus installed


def test_deployment_observer():
    """Test deployment observer recording events."""
    observer = DeploymentObserver("test-001", "production")
    
    # Record events
    observer.record_event("deployment_started", {"version": "1.0.0"})
    observer.record_sequence_completion("primary", True, 2.5)
    observer.record_health_check_result("db-check", True)
    observer.record_gap_detected("Missing cache", "warning")
    observer.finalize(True)
    
    # Get events
    events = observer.get_events()
    assert len(events) == 5
    assert events[0]["type"] == "deployment_started"
    assert events[-1]["type"] == "deployment_success"


def test_alert_manager():
    """Test alert manager initialization."""
    am = AlertManager()
    
    # Add channels (won't actually send without real URLs)
    am.add_slack_channel("http://localhost:3000/hook")
    am.add_github_channel("owner", "repo", "fake-token")
    
    # Verify channels added
    assert len(am.channels) == 2


def test_prometheus_rules():
    """Test Prometheus rules generation."""
    rules = get_prometheus_rules()
    assert "remediation_attempts_total" in rules
    assert "alert: RemediationHighFailureRate" in rules
    assert "alert: DeploymentFailed" in rules


def test_grafana_dashboard():
    """Test Grafana dashboard generation."""
    dashboard = get_grafana_dashboard()
    assert "dashboard" in dashboard
    assert dashboard["dashboard"]["title"] == "Self-Healing Orchestrator"
    assert len(dashboard["dashboard"]["panels"]) > 0


if __name__ == "__main__":
    test_metrics_collector_basic()
    test_deployment_observer()
    test_alert_manager()
    test_prometheus_rules()
    test_grafana_dashboard()
    print("✓ All monitoring tests passed")
