"""
Circuit Breaker Pattern Implementation
FAANG Enterprise Standard: Resilience & Fault Tolerance
Protects services from cascading failures via external API calls
"""

import time
import threading
from enum import Enum
from typing import Callable, Any, Dict, Optional, List
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)


class CircuitState(Enum):
    """Circuit breaker states"""
    CLOSED = "closed"          # Normal operation
    OPEN = "open"              # Failing - reject calls
    HALF_OPEN = "half_open"    # Recovery attempt - single call allowed


@dataclass
class CircuitBreakerConfig:
    """Configuration for circuit breaker behavior"""
    failure_threshold: int = 5           # Failures before opening
    recovery_timeout: int = 60            # Seconds before attempting recovery
    expected_exception: type = Exception   # Exception type to catch
    name: str = "default"
    success_threshold: int = 2            # Successes in HALF_OPEN before closing
    metrics_enabled: bool = True
    

@dataclass
class CircuitBreakerMetrics:
    """Metrics tracking for circuit breaker"""
    total_calls: int = 0
    successful_calls: int = 0
    failed_calls: int = 0
    rejected_calls: int = 0  # Calls rejected because circuit was OPEN
    state_changes: List[Dict[str, Any]] = field(default_factory=list)
    last_state_change: Optional[datetime] = None
    
    def reset(self):
        """Reset metrics"""
        self.total_calls = 0
        self.successful_calls = 0
        self.failed_calls = 0
        self.rejected_calls = 0
        self.state_changes.clear()
        self.last_state_change = None


class CircuitBreaker:
    """
    Circuit Breaker pattern for external API calls
    Prevents cascading failures by failing fast when a service is down
    """
    
    def __init__(self, config: CircuitBreakerConfig):
        self.config = config
        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.success_count = 0
        self.last_failure_time: Optional[datetime] = None
        self.metrics = CircuitBreakerMetrics()
        self._lock = threading.RLock()
        
    def call(self, fn: Callable, *args, **kwargs) -> Any:
        """
        Execute function with circuit breaker protection
        
        Args:
            fn: Callable to execute (typically API call)
            *args: Positional arguments for fn
            **kwargs: Keyword arguments for fn
            
        Returns:
            Result of fn() if successful
            
        Raises:
            CircuitBreakerOpenException: If circuit is open
            Exception: Original exception from fn if it fails
        """
        with self._lock:
            self.metrics.total_calls += 1
            
            if self.state == CircuitState.OPEN:
                if self._should_attempt_reset():
                    self._transition_to_half_open()
                else:
                    self.metrics.rejected_calls += 1
                    raise CircuitBreakerOpenException(
                        f"Circuit breaker '{self.config.name}' is open. "
                        f"Service unavailable. Retry after {self._get_retry_after()}s"
                    )
        
        try:
            result = fn(*args, **kwargs)
            self._on_success()
            return result
            
        except self.config.expected_exception as e:
            self._on_failure()
            raise
            
        except Exception as e:
            # Don't count unexpected exceptions towards circuit breaker
            logger.warning(f"Unexpected exception in {self.config.name}: {e}")
            raise
    
    def _on_success(self):
        """Handle successful call"""
        with self._lock:
            self.metrics.successful_calls += 1
            self.failure_count = 0
            
            if self.state == CircuitState.HALF_OPEN:
                self.success_count += 1
                if self.success_count >= self.config.success_threshold:
                    self._transition_to_closed()
    
    def _on_failure(self):
        """Handle failed call"""
        with self._lock:
            self.metrics.failed_calls += 1
            self.failure_count += 1
            self.last_failure_time = datetime.now()
            
            if self.state == CircuitState.HALF_OPEN:
                # Failed recovery attempt - go back to open
                self._transition_to_open()
            elif self.failure_count >= self.config.failure_threshold:
                # Too many failures in closed state - open circuit
                self._transition_to_open()
    
    def _should_attempt_reset(self) -> bool:
        """Check if enough time has passed to attempt recovery"""
        if self.last_failure_time is None:
            return True
        
        elapsed = (datetime.now() - self.last_failure_time).total_seconds()
        return elapsed >= self.config.recovery_timeout
    
    def _get_retry_after(self) -> int:
        """Get recommended retry time in seconds"""
        if self.last_failure_time is None:
            return self.config.recovery_timeout
        
        elapsed = (datetime.now() - self.last_failure_time).total_seconds()
        remaining = self.config.recovery_timeout - elapsed
        return max(0, int(remaining))
    
    def _transition_to_open(self):
        """Transition to OPEN state"""
        self.state = CircuitState.OPEN
        self.success_count = 0
        self.metrics.state_changes.append({
            "timestamp": datetime.now().isoformat(),
            "state": CircuitState.OPEN.value,
            "failure_count": self.failure_count
        })
        logger.warning(f"Circuit breaker '{self.config.name}' opened - service unavailable")
    
    def _transition_to_half_open(self):
        """Transition to HALF_OPEN state"""
        self.state = CircuitState.HALF_OPEN
        self.success_count = 0
        self.failure_count = 0
        self.metrics.state_changes.append({
            "timestamp": datetime.now().isoformat(),
            "state": CircuitState.HALF_OPEN.value,
            "recovery_attempt": True
        })
        logger.info(f"Circuit breaker '{self.config.name}' attempting recovery")
    
    def _transition_to_closed(self):
        """Transition to CLOSED state"""
        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.success_count = 0
        self.metrics.state_changes.append({
            "timestamp": datetime.now().isoformat(),
            "state": CircuitState.CLOSED.value,
            "recovery_successful": True
        })
        logger.info(f"Circuit breaker '{self.config.name}' closed - service recovered")
    
    def get_state(self) -> str:
        """Get current circuit state"""
        return self.state.value
    
    def get_metrics(self) -> Dict[str, Any]:
        """Get circuit breaker metrics"""
        with self._lock:
            return {
                "name": self.config.name,
                "state": self.state.value,
                "total_calls": self.metrics.total_calls,
                "successful_calls": self.metrics.successful_calls,
                "failed_calls": self.metrics.failed_calls,
                "rejected_calls": self.metrics.rejected_calls,
                "success_rate": (
                    self.metrics.successful_calls / self.metrics.total_calls * 100
                    if self.metrics.total_calls > 0 else 0
                ),
                "state_changes": self.metrics.state_changes[-10:],  # Last 10 changes
                "failure_count": self.failure_count,
                "recovery_timeout": self.config.recovery_timeout,
            }
    
    def reset(self):
        """Reset circuit breaker to initial state"""
        with self._lock:
            self.state = CircuitState.CLOSED
            self.failure_count = 0
            self.success_count = 0
            self.last_failure_time = None
            self.metrics.reset()
            logger.info(f"Circuit breaker '{self.config.name}' reset")


class CircuitBreakerOpenException(Exception):
    """Raised when circuit breaker is open"""
    pass


class CircuitBreakerRegistry:
    """
    Registry to manage multiple circuit breakers
    FAANG Pattern: Centralized management & monitoring
    """
    
    def __init__(self):
        self._breakers: Dict[str, CircuitBreaker] = {}
        self._lock = threading.RLock()
    
    def register(self, config: CircuitBreakerConfig) -> CircuitBreaker:
        """Register a new circuit breaker"""
        with self._lock:
            if config.name in self._breakers:
                logger.warning(f"Circuit breaker '{config.name}' already registered")
                return self._breakers[config.name]
            
            breaker = CircuitBreaker(config)
            self._breakers[config.name] = breaker
            logger.info(f"Registered circuit breaker: {config.name}")
            return breaker
    
    def get(self, name: str) -> Optional[CircuitBreaker]:
        """Get circuit breaker by name"""
        return self._breakers.get(name)
    
    def get_all_metrics(self) -> Dict[str, Dict[str, Any]]:
        """Get metrics for all circuit breakers"""
        with self._lock:
            return {
                name: breaker.get_metrics()
                for name, breaker in self._breakers.items()
            }
    
    def reset_all(self):
        """Reset all circuit breakers"""
        with self._lock:
            for breaker in self._breakers.values():
                breaker.reset()
            logger.info("Reset all circuit breakers")


# Global registry singleton
_registry = CircuitBreakerRegistry()


def get_circuit_breaker_registry() -> CircuitBreakerRegistry:
    """Get global circuit breaker registry"""
    return _registry


# Example usage and decorator
def circuit_breaker(config: CircuitBreakerConfig):
    """
    Decorator for adding circuit breaker protection to functions
    
    Example:
        @circuit_breaker(CircuitBreakerConfig(
            name="external_payment_api",
            failure_threshold=5,
            recovery_timeout=60
        ))
        def call_payment_api(amount):
            response = requests.post("https://api.payment.com/charge", ...)
            return response.json()
    """
    breaker = _registry.register(config)
    
    def decorator(fn: Callable) -> Callable:
        def wrapper(*args, **kwargs):
            return breaker.call(fn, *args, **kwargs)
        return wrapper
    
    return decorator


# Example: Health check endpoint for observability
def get_circuit_breaker_health() -> Dict[str, Any]:
    """
    Returns health status of all circuit breakers
    Suitable for /health endpoint in API
    """
    metrics = _registry.get_all_metrics()
    
    # Determine overall health
    states = [m["state"] for m in metrics.values()]
    open_count = states.count("open")
    half_open_count = states.count("half_open")
    
    health_status = "healthy"
    if open_count > 0:
        health_status = "degraded"
    if open_count > len(metrics) / 2:
        health_status = "unhealthy"
    
    return {
        "status": health_status,
        "timestamp": datetime.now().isoformat(),
        "circuit_breakers": metrics,
        "summary": {
            "total_breakers": len(metrics),
            "open": open_count,
            "half_open": half_open_count,
            "closed": len(metrics) - open_count - half_open_count,
        }
    }


if __name__ == "__main__":
    # Example usage
    logging.basicConfig(level=logging.INFO)
    
    # Create circuit breaker config
    config = CircuitBreakerConfig(
        name="external_api",
        failure_threshold=3,
        recovery_timeout=5,
        expected_exception=Exception
    )
    
    # Register and get breaker
    breaker = _registry.register(config)
    
    # Simulate calls
    def flaky_api_call(should_fail: bool):
        if should_fail:
            raise Exception("API call failed")
        return {"status": "ok"}
    
    # Test circuit breaker behavior
    print("\n=== Circuit Breaker Test ===")
    print(f"Initial state: {breaker.get_state()}")
    
    # Make successful calls
    print("\n1. Making 2 successful calls...")
    breaker.call(flaky_api_call, False)
    breaker.call(flaky_api_call, False)
    print(f"State after success: {breaker.get_state()}")
    
    # Make failing calls to trigger open
    print("\n2. Making 3 failing calls to trigger OPEN...")
    for i in range(3):
        try:
            breaker.call(flaky_api_call, True)
        except Exception as e:
            print(f"  Call {i+1} failed: {e}")
    
    print(f"State after failures: {breaker.get_state()}")
    
    # Try to call while open
    print("\n3. Attempting call while circuit is OPEN...")
    try:
        breaker.call(flaky_api_call, False)
    except CircuitBreakerOpenException as e:
        print(f"  Rejected: {e}")
    
    # Print metrics
    print("\n4. Circuit Breaker Metrics:")
    import json
    print(json.dumps(breaker.get_metrics(), indent=2, default=str))
