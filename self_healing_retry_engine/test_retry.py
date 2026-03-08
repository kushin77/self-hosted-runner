import pytest
import pytest
import time

from self_healing_retry_engine.retry import RetryEngine, CircuitBreakerOpen


class TransientError(Exception):
    pass


class PermanentError(Exception):
    pass


def test_retry_succeeds_after_transient_retries(monkeypatch):
    calls = {"n": 0}

    def flaky():
        calls["n"] += 1
        if calls["n"] < 3:
            raise TransientError("transient")
        return "ok"

    engine = RetryEngine(max_attempts=5, base_delay=0.01, jitter=0.0,
                         is_transient=lambda e: isinstance(e, TransientError))
    res = engine.call(flaky)
    assert res == "ok"
    assert calls["n"] == 3


def test_retry_raises_on_permanent_error():
    def bad():
        raise PermanentError("boom")

    engine = RetryEngine(max_attempts=3, is_transient=lambda e: False)
    with pytest.raises(PermanentError):
        engine.call(bad)


def test_circuit_breaker_opens(monkeypatch):
    def always_fail():
        raise TransientError("t")

    engine = RetryEngine(max_attempts=1, cb_fail_threshold=2, cb_reset_timeout=0.1,
                         is_transient=lambda e: True)

    # Two failures to open circuit
    with pytest.raises(TransientError):
        engine.call(always_fail)
    with pytest.raises(TransientError):
        engine.call(always_fail)

    # Circuit should be open now
    with pytest.raises(CircuitBreakerOpen):
        engine.call(always_fail)

    # Wait for reset
    time.sleep(0.12)
    with pytest.raises(TransientError):
        engine.call(always_fail)

from self_healing_retry_engine.retry import RetryEngine, CircuitBreakerOpen


class TransientError(Exception):
    pass


class PermanentError(Exception):
    pass


def test_retry_succeeds_after_transient_retries(monkeypatch):
    calls = {"n": 0}

    def flaky():
        calls["n"] += 1
        if calls["n"] < 3:
            raise TransientError("transient")
        return "ok"

    engine = RetryEngine(max_attempts=5, base_delay=0.01, jitter=0.0,
                         is_transient=lambda e: isinstance(e, TransientError))
    res = engine.call(flaky)
    assert res == "ok"
    assert calls["n"] == 3


def test_retry_raises_on_permanent_error():
    def bad():
        raise PermanentError("boom")

    engine = RetryEngine(max_attempts=3, is_transient=lambda e: False)
    with pytest.raises(PermanentError):
        engine.call(bad)


def test_circuit_breaker_opens(monkeypatch):
    def always_fail():
        raise TransientError("t")

    engine = RetryEngine(max_attempts=1, cb_fail_threshold=2, cb_reset_timeout=0.1,
                         is_transient=lambda e: True)

    # Two failures to open circuit
    with pytest.raises(TransientError):
        engine.call(always_fail)
    with pytest.raises(TransientError):
        engine.call(always_fail)

    # Circuit should be open now
    with pytest.raises(CircuitBreakerOpen):
        engine.call(always_fail)

    # Wait for reset
    time.sleep(0.12)
    with pytest.raises(TransientError):
        engine.call(always_fail)
>>>>>>> 2e570800c (feat(retry): implement RetryEngine (backoff + circuit breaker) + tests)
