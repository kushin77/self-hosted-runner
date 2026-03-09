import json
import os
import tempfile
import time
from typing import Any, Dict, Optional


class CheckpointStore:
    """Simple checkpoint writer/reader using atomic file replace.

    Stores a JSON blob per workflow id under a directory. Designed to be
    idempotent: writing the same checkpoint is safe, and readers can resume
    from the last checkpoint.
    """

    def __init__(self, path: str = ".checkpoints"):
        self.path = path
        os.makedirs(self.path, exist_ok=True)

    def _filepath(self, workflow_id: str) -> str:
        safe = workflow_id.replace("/", "_")
        return os.path.join(self.path, f"{safe}.json")

    def write_checkpoint(self, workflow_id: str, state: Dict[str, Any]):
        tmpfd, tmppath = tempfile.mkstemp(dir=self.path)
        try:
            with os.fdopen(tmpfd, "w") as f:
                json.dump({"ts": time.time(), "state": state}, f)
            # Atomic replace
            os.replace(tmppath, self._filepath(workflow_id))
        finally:
            if os.path.exists(tmppath):
                try:
                    os.remove(tmppath)
                except Exception:
                    pass

    def read_checkpoint(self, workflow_id: str) -> Optional[Dict[str, Any]]:
        p = self._filepath(workflow_id)
        if not os.path.exists(p):
            return None
        try:
            with open(p, "r") as f:
                return json.load(f)
        except Exception:
            return None

    def clear_checkpoint(self, workflow_id: str):
        p = self._filepath(workflow_id)
        if os.path.exists(p):
            os.remove(p)


__all__ = ["CheckpointStore"]
