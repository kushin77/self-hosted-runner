import logging
from typing import Optional, Dict, List, Any, Callable
from enum import Enum
from datetime import datetime

logger = logging.getLogger(__name__)

class HealthCheckType(Enum):
    ENDPOINT = "endpoint"
    ERROR_RATE = "error_rate"
    LATENCY = "latency"
    CUSTOM = "custom"

class HealthChecker:
    def __init__(self):
        self.checks = []
        self.results = {}
    def register_check(self, name: str, check_type: HealthCheckType, config: Dict[str, Any], handler: Optional[Callable] = None):
        self.checks.append({"name": name, "type": check_type.value, "config": config, "handler": handler})
        logger.info(f"Health check registered: {name}")
    def endpoint_check(self, endpoint_url: str, timeout_seconds: int = 5) -> bool:
        try:
            import requests
            response = requests.get(endpoint_url, timeout=timeout_seconds)
            status_ok = 200 <= response.status_code < 300
            logger.info(f"Endpoint {endpoint_url}: {response.status_code} → {status_ok}")
            return status_ok
        except Exception as e:
            logger.error(f"Endpoint check failed: {e}")
            return False
    def run_all_checks(self) -> Dict[str, bool]:
        self.results = {}
        for check in self.checks:
            try:
                name = check["name"]
                if check["handler"]:
                    result = check["handler"](check["config"])
                elif check["type"] == HealthCheckType.ENDPOINT.value:
                    result = self.endpoint_check(check["config"].get("url", ""))
                else:
                    result = False
                self.results[name] = result
            except Exception as e:
                logger.error(f"Check failed: {e}")
                self.results[check["name"]] = False
        return self.results
    def all_healthy(self) -> bool:
        return all(self.results.values())

class RollbackStrategy(Enum):
    BLUE_GREEN = "blue_green"
    CANARY = "canary"
    IMMEDIATE = "immediate"

class RollbackExecutor:
    def __init__(self):
        self.audit_trail = []
    def should_rollback(self, health_results: Dict[str, bool], severity_threshold: float = 0.5) -> bool:
        if not health_results:
            return False
        failures = sum(1 for result in health_results.values() if not result)
        severity = failures / len(health_results)
        should_rb = severity >= severity_threshold
        logger.info(f"Rollback decision: {failures}/{len(health_results)} failed → {should_rb}")
        return should_rb
    def execute_rollback(self, deployment_id: str, strategy: RollbackStrategy = RollbackStrategy.BLUE_GREEN) -> bool:
        try:
            logger.info(f"Executing rollback ({strategy.value}): {deployment_id}")
            self.audit_trail.append({"timestamp": datetime.utcnow().isoformat(), "deployment_id": deployment_id, "strategy": strategy.value, "success": True})
            return True
        except Exception as e:
            logger.error(f"Rollback failed: {e}")
            return False
    def get_audit_trail(self) -> List[Dict[str, Any]]:
        return self.audit_trail

_health_checker = None
_rollback_executor = None

def get_health_checker() -> HealthChecker:
    global _health_checker
    if _health_checker is None:
        _health_checker = HealthChecker()
    return _health_checker

def get_rollback_executor() -> RollbackExecutor:
    global _rollback_executor
    if _rollback_executor is None:
        _rollback_executor = RollbackExecutor()
    return _rollback_executor
