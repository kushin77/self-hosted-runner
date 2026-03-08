import pytest
<<<<<<< HEAD
from self_healing_retry_engine.retry import RetryEngine, CircuitOpenError

def test_backoff_delay_range():
    r = RetryEngine(base_delay=0.1, max_delay=1.0)
    d0 = r.backoff_delay(0)
    d3 = r.backoff_delay(3)
    assert d0 >= 0.1
    assert d3 <= 1.0 + 0.1


def test_classifier_placeholder():
    r = RetryEngine()
    assert r.classify_error(Exception('x')) in ('transient',)


def test_retry_call_success():
    r = RetryEngine(base_delay=0.01, max_retries=3)
    state = {'count':0}
    def flaky():
        state['count'] += 1
        if state['count'] < 3:
            raise RuntimeError('temporary')
        return 'ok'
    assert r.call(flaky) == 'ok'


def test_circuit_open_behavior():
    r = RetryEngine(max_retries=0)
    def always_fail():
        raise RuntimeError('fail')
    with pytest.raises(RuntimeError):
        r.call(always_fail)
    # simulate many failures to open circuit
    r._failure_count = r._circuit_threshold
    r._circuit_open = True
    with pytest.raises(CircuitOpenError):
        r.call(lambda: None)
=======
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
>>>>>>> 2e570800c (feat(retry): implement RetryEngine (backoff + circuit breaker) + tests)
