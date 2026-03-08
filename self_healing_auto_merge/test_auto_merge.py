import pytest
import time

from self_healing_auto_merge.auto_merge import AutoMergeManager, MergeRejected


def dummy_merge(pr):
    pr.setdefault("merged", 0)
    pr["merged"] += 1
    return True


def dummy_rollback(pr):
    pr.setdefault("rolled_back", 0)
    pr["rolled_back"] += 1
    return True


def test_schedule_merge_low():
    mgr = AutoMergeManager(lambda pr: "LOW")
    pr = {"id": 1}
    t = mgr.schedule_merge(pr, dummy_merge, delay_seconds=0)
    # give thread a moment
    time.sleep(0.05)
    assert pr.get("merged", 0) == 1


def test_schedule_merge_critical_rejected():
    mgr = AutoMergeManager(lambda pr: "CRITICAL")
    pr = {"id": 2}
    with pytest.raises(MergeRejected):
        mgr.schedule_merge(pr, dummy_merge)


def test_rollback_hook():
    mgr = AutoMergeManager()
    pr = {"id": 3}
    mgr.rollback_hook(pr, dummy_rollback)
    assert pr.get("rolled_back", 0) == 1
>>>>>>> 1379a4e11 (feat(auto-merge): implementation + package init)
import pytest
import time

from self_healing_auto_merge.auto_merge import AutoMergeManager, MergeRejected


def dummy_merge(pr):
    pr.setdefault("merged", 0)
    pr["merged"] += 1
    return True


def dummy_rollback(pr):
    pr.setdefault("rolled_back", 0)
    pr["rolled_back"] += 1
    return True


def test_schedule_merge_low():
    mgr = AutoMergeManager(lambda pr: "LOW")
    pr = {"id": 1}
    t = mgr.schedule_merge(pr, dummy_merge, delay_seconds=0)
    # give thread a moment
    time.sleep(0.05)
    assert pr.get("merged", 0) == 1


def test_schedule_merge_critical_rejected():
    mgr = AutoMergeManager(lambda pr: "CRITICAL")
    pr = {"id": 2}
    with pytest.raises(MergeRejected):
        mgr.schedule_merge(pr, dummy_merge)


def test_rollback_hook():
    mgr = AutoMergeManager()
    pr = {"id": 3}
    mgr.rollback_hook(pr, dummy_rollback)
    assert pr.get("rolled_back", 0) == 1
>>>>>>> 1379a4e11 (feat(auto-merge): implementation + package init)
