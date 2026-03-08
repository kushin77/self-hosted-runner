import time

from self_healing_pr_prioritization.pr_prioritization import PRPrioritizer


def test_classify_and_schedule():
    called = {}

    def merge_fn(pr):
        called['id'] = pr['id']

    p = PRPrioritizer(lambda pr: "HIGH")
    pr = {"id": 123}
    # schedule with a small delay window
    t = p.schedule(pr, merge_fn, priority_windows={"HIGH": 0.01})
    time.sleep(0.05)
    assert called.get('id') == 123
