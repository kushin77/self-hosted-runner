import os
import shutil

from self_healing_state.state import CheckpointStore


def test_checkpoint_write_and_read(tmp_path):
    d = tmp_path / "checkpoints"
    store = CheckpointStore(str(d))
    wid = "wf-1"
    state = {"step": 3, "done": [1, 2]}
    store.write_checkpoint(wid, state)
    data = store.read_checkpoint(wid)
    assert data is not None
    assert data["state"]["step"] == 3
    store.clear_checkpoint(wid)
    assert store.read_checkpoint(wid) is None
