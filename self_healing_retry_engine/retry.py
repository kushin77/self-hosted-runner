import time
import random
import threading
from typing import Callable, Any, Optional


class CircuitBreakerOpen(Exception):
    pass


class RetryEngine:
    """A small, testable retry engine with exponential backoff, jitter and a
    minimal circuit breaker. Error classification is pluggable via
    `is_transient` callable.

    Usage:
        engine = RetryEngine()
        result = engine.call(my_fn, args...)
    """

    def __init__(self,
                 max_attempts: int = 5,
                 base_delay: float = 0.5,
                 max_delay: float = 30.0,
                 jitter: float = 0.1,
                 cb_fail_threshold: int = 10,
                 cb_reset_timeout: float = 60.0,
                 is_transient: Optional[Callable[[Exception], bool]] = None):
        self.max_attempts = max_attempts
        self.base_delay = base_delay
        self.max_delay = max_delay
        self.jitter = jitter
        self.is_transient = is_transient or (lambda e: True)

        # Circuit breaker state
        self._cb_fail_threshold = cb_fail_threshold
        self._cb_reset_timeout = cb_reset_timeout
        self._cb_fail_count = 0
        self._cb_open_until = 0.0
        self._lock = threading.Lock()

    def _circuit_allows(self) -> bool:
        with self._lock:
            now = time.time()
            if self._cb_open_until and now < self._cb_open_until:
                return False
            return True

    def _record_failure(self):
        with self._lock:
            self._cb_fail_count += 1
            if self._cb_fail_count >= self._cb_fail_threshold:
                self._cb_open_until = time.time() + self._cb_reset_timeout

    def _record_success(self):
        with self._lock:
            self._cb_fail_count = 0
            self._cb_open_until = 0.0

    def _sleep_backoff(self, attempt: int):
        expo = min(self.max_delay, self.base_delay * (2 ** (attempt - 1)))
        jitter = random.uniform(0, self.jitter * expo)
        delay = expo + jitter
        time.sleep(delay)

    def call(self, func: Callable, *args, **kwargs) -> Any:
        """Call `func(*args, **kwargs)` with retries.

        Raises the last exception if all retries fail or `CircuitBreakerOpen`.
        """
        if not self._circuit_allows():
            raise CircuitBreakerOpen("Circuit breaker is open")

        last_exc = None
        for attempt in range(1, self.max_attempts + 1):
            try:
                res = func(*args, **kwargs)
                self._record_success()
                return res
            except Exception as exc:
                last_exc = exc
                if not self.is_transient(exc):
                    # Permanent error; don't retry
                    self._record_failure()
                    raise
                # Transient: record failure and possibly backoff
                self._record_failure()
                if attempt == self.max_attempts:
                    break
                self._sleep_backoff(attempt)

        # If here, all attempts exhausted
        raise last_exc


__all__ = ["RetryEngine", "CircuitBreakerOpen"]
