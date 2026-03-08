"""GitHub adapters for PR merge, issue creation, and workflow triggers.

These adapters attempt to use the `gh` CLI when available for lightweight
integration. They are intentionally small wrappers so they can be used as
RemediationStep actions or from the EscalationManager.
"""
import json
import logging
import shlex
import subprocess
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)


def _run_cmd(cmd: str) -> Dict[str, Any]:
    try:
        out = subprocess.check_output(shlex.split(cmd), stderr=subprocess.STDOUT)
        return {"ok": True, "output": out.decode("utf-8")}
    except subprocess.CalledProcessError as e:
        logger.exception("Command failed: %s", cmd)
        return {"ok": False, "error": e.output.decode("utf-8") if e.output else str(e)}


def merge_pr(pr_number: int, method: str = "merge", repo: Optional[str] = None) -> bool:
    """Merge a PR using `gh` CLI. Method can be 'merge', 'squash', or 'rebase'."""
    repo_arg = f"--repo {repo}" if repo else ""
    cmd = f"gh pr merge {pr_number} --{method} --yes {repo_arg}"
    res = _run_cmd(cmd)
    return res.get("ok", False)


def create_issue(title: str, body: str, repo: Optional[str] = None, labels: Optional[list] = None) -> bool:
    repo_arg = f"--repo {repo}" if repo else ""
    labels_arg = "" if not labels else f"--label {','.join(labels)}"
    # Use gh issue create with JSON output
    cmd = f"gh issue create --title {shlex.quote(title)} --body {shlex.quote(body)} {labels_arg} {repo_arg} --json number,url"
    res = _run_cmd(cmd)
    return res.get("ok", False)


def trigger_workflow(workflow: str, ref: str = "main", repo: Optional[str] = None) -> bool:
    repo_arg = f"--repo {repo}" if repo else ""
    cmd = f"gh workflow run {workflow} --ref {ref} {repo_arg}"
    res = _run_cmd(cmd)
    return res.get("ok", False)


__all__ = ["merge_pr", "create_issue", "trigger_workflow"]
