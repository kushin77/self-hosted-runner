import pytest
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
