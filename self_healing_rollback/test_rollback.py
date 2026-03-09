import time

from self_healing_rollback.rollback import HealthCheckOrchestrator, RollbackExecutor


def test_healthcheck_and_rollback_trigger():
    checks = {
        "endpoint": lambda: False,
        "errors": lambda: False,
    }
    orch = HealthCheckOrchestrator(checks)
    results = orch.run_checks()
    assert results["endpoint"] is False
    assert orch.should_rollback(results, error_rate_threshold=0.1) is True


def test_rollback_executor_calls_fn():
    called = {}

    def rb_fn(deployment_id):
        called["id"] = deployment_id
        return True

    exec = RollbackExecutor()
    res = exec.execute_rollback("dep-1", rb_fn)
    assert res is True
    assert called["id"] == "dep-1"
