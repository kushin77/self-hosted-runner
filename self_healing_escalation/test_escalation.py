from self_healing_escalation.escalation import EscalationManager


def test_notify_and_dedup():
    sent = []

    def slack(msg):
        sent.append(("slack", msg))

    em = EscalationManager()
    key = "job-1"
    res = em.notify(key, "oops", level=1, slack_fn=slack, cooldown=1.0)
    assert res == ["slack"]
    # immediate second notify should be deduped
    res2 = em.notify(key, "oops", level=1, slack_fn=slack, cooldown=10.0)
    assert res2 == []


def test_acknowledge():
    em = EscalationManager()
    key = "job-2"
    assert not em.is_acknowledged(key)
    em.acknowledge(key)
    assert em.is_acknowledged(key)
