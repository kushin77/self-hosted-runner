"""RetryEngine scaffold: exponential backoff + circuit breaker stub + classifier placeholder."""
import time
import random

class CircuitOpenError(Exception):
    pass

class RetryEngine:
    def __init__(self, base_delay=0.5, max_delay=30.0, max_retries=5):
        self.base_delay = base_delay
        self.max_delay = max_delay
        self.max_retries = max_retries
        # circuit breaker state (very small stub)
        self._circuit_open = False
        self._failure_count = 0
        self._circuit_threshold = 10

    # Placeholder classifier - replace with ML/heuristic later
    def classify_error(self, exc):
        return 'transient'

    def should_retry(self, exc, attempt):
        if self._circuit_open:
            return False
        cls = self.classify_error(exc)
        return cls == 'transient' and attempt < self.max_retries

    def backoff_delay(self, attempt):
        delay = min(self.base_delay * (2 ** attempt), self.max_delay)
        # small jitter to avoid thundering herds
        jitter = random.uniform(0, delay * 0.1)
        return delay + jitter

    def _record_failure(self):
        self._failure_count += 1
        if self._failure_count >= self._circuit_threshold:
            self._circuit_open = True

    def reset_circuit(self):
        self._failure_count = 0
        self._circuit_open = False

    def call(self, func, *args, **kwargs):
        attempt = 0
        while True:
            if self._circuit_open:
                raise CircuitOpenError("Circuit is open; rejecting call")
            try:
                result = func(*args, **kwargs)
                # success resets circuit
                self.reset_circuit()
                return result
            except Exception as e:
                self._record_failure()
                if not self.should_retry(e, attempt):
                    raise
                delay = self.backoff_delay(attempt)
                time.sleep(delay)
                attempt += 1
