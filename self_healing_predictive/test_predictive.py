import time

from self_healing_predictive.predictive import PredictiveHealer, RemediationAction


def test_predictive_executes_action(monkeypatch):
    called = {}

    def remediate(ctx):
        called['ok'] = True

    ph = PredictiveHealer(cooldown_seconds=0.1)
    ph.register_rule(r"timeout", RemediationAction("fix_timeout", remediate))
    ctx = {"message": "task failed with timeout"}
    executed = ph.evaluate(ctx)
    assert executed == ["fix_timeout"]
    assert called.get('ok') is True


def test_cooldown_blocks_repeated_heal(monkeypatch):
    calls = {"n": 0}

    def remediate(ctx):
        calls['n'] += 1

    ph = PredictiveHealer(cooldown_seconds=0.2)
    ph.register_rule(r"exhausted", RemediationAction("scale_up", remediate))
    ctx = {"message": "resource exhausted"}
    assert ph.evaluate(ctx) == ["scale_up"]
    # immediate second call should be blocked by cooldown
    assert ph.evaluate(ctx) == []
    time.sleep(0.22)
    # after cooldown, allowed again
    assert ph.evaluate(ctx) == ["scale_up"]
    assert calls['n'] == 2
