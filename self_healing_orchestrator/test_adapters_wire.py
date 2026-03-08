from self_healing_orchestrator.adapters.wire_modules import wire_default_sequences
from self_healing_orchestrator.integration import SelfHealingOrchestrationIntegration


def test_wire_and_run_smoke():
    integration = SelfHealingOrchestrationIntegration(deployment_id="test-deploy", environment="test")
    wire_default_sequences(integration)
    result = integration.execute_full_orchestration()
    # Integration uses a basic health check that returns True; ensure structure exists
    assert isinstance(result, dict)
    assert "status" in result
    assert "report" in result
