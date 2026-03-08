from self_healing_auto_merge.auto_merge import AutoMergeManager


def test_evaluate_and_schedule():
    m = AutoMergeManager()
    pr = {'id': 1, 'title': 'test'}
    # default policy: low -> enabled True
    res = m.schedule_merge(pr)
    assert res.get('scheduled') is True


def test_hooks_are_called():
    m = AutoMergeManager()
    called = {}
    def schedule_hook(pr):
        called['s'] = True
        return {'scheduled': True, 'hook': True}
    def rollback_hook(pr):
        called['r'] = True
        return {'rolled_back': True, 'hook': True}
    m.set_schedule_hook(schedule_hook)
    m.set_rollback_hook(rollback_hook)
    assert m.schedule_merge({'id':2})['hook'] is True
    assert m.rollback_merge({'id':2})['hook'] is True
    assert called['s'] and called['r']
