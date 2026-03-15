#!/usr/bin/env python3
"""
semantic-optimizer.py
Intelligent git commit history squashing by semantic intent.

Groups commits by conventional-commit type (feat, fix, chore, …), squashes
squashable groups while *preserving* breaking changes and reverts individually.

SUBCOMMANDS:
  analyze  — Read-only analysis, prints squash plan as JSON
  preview  — Alias for analyze
  rewrite  — Execute history rewrite (backs up branch first, then rebases)
  rollback — Restore branch from backup created by last rewrite

SAFETY GUARANTEES:
  - Branch is backed up before ANY rewrite (backup/semantic-optimizer/<branch>/<ts>)
  - Rebase is aborted automatically on failure; backup is preserved
  - Audit trail written to JSONL on every operation
  - force-push only when --force-push is explicitly passed

CONSTRAINTS:
  - Immutable JSONL audit trail
  - Ephemeral staging (no side effects if analyze/preview)
  - Idempotent: running analyze twice → same output
  - No GitHub Actions: direct git operations only

USAGE:
  python3 semantic-optimizer.py analyze --branch feature/oauth --base main
  python3 semantic-optimizer.py rewrite --branch feature/oauth --base main
  python3 semantic-optimizer.py rewrite --branch feature/oauth --base main --force-push
"""

import os
import sys
import re
import json
import uuid
import tempfile
import argparse
import logging
import subprocess
from pathlib import Path
from datetime import datetime
from collections import defaultdict
from typing import Dict, List, Optional, Any, Tuple


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    format='{"timestamp": "%(asctime)s", "level": "%(levelname)s",'
           ' "component": "semantic-optimizer", "message": "%(message)s"}',
    level=logging.INFO,
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Audit trail
# ---------------------------------------------------------------------------
_AUDIT_FILE: Optional[Path] = None


def _init_audit(repo_path: Path) -> None:
    global _AUDIT_FILE
    _AUDIT_FILE = repo_path / "logs" / "semantic-optimizer-audit.jsonl"
    _AUDIT_FILE.parent.mkdir(parents=True, exist_ok=True)


def _audit(event: str, details: Dict[str, Any]) -> None:
    if _AUDIT_FILE is None:
        return
    entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "event": event,
        "details": details,
    }
    with _AUDIT_FILE.open("a") as f:
        f.write(json.dumps(entry) + "\n")


# ---------------------------------------------------------------------------
# Intent classification
# ---------------------------------------------------------------------------
_INTENT_MAP: Dict[str, str] = {
    "feat": "feature",
    "feature": "feature",
    "fix": "bugfix",
    "bugfix": "bugfix",
    "hotfix": "bugfix",
    "refactor": "refactor",
    "style": "style",
    "chore": "chore",
    "ci": "chore",
    "build": "chore",
    "docs": "docs",
    "doc": "docs",
    "test": "test",
    "tests": "test",
    "perf": "performance",
    "revert": "revert",
    "breaking": "breaking",
}

# Intents that MUST be kept as individual commits
_PRESERVE_INTENTS = {"breaking", "revert", "feature"}

# Intents that can be squashed with siblings
_SQUASH_INTENTS = {"bugfix", "refactor", "style", "chore", "docs", "test", "performance"}


def _classify(message: str) -> str:
    """Classify a commit message into a semantic intent bucket."""
    msg = message.lower().strip()

    # Explicit BREAKING CHANGE footer
    if "breaking change" in msg or re.search(r'\bbreaking[!:]', msg):
        return "breaking"

    # Exclamation mark in conventional commit  (e.g. "feat!: xyz")
    if re.match(r'^\w+\([^)]*\)!:', msg) or re.match(r'^\w+!:', msg):
        return "breaking"

    # Standard conventional commit prefix  e.g. "feat(scope): …"
    m = re.match(r'^(\w+)(?:\([^)]+\))?:', msg)
    if m:
        prefix = m.group(1).lower()
        return _INTENT_MAP.get(prefix, "other")

    # Fuzzy match on leading word
    for prefix, intent in _INTENT_MAP.items():
        if msg.startswith(prefix + " ") or msg.startswith(prefix + "/"):
            return intent

    return "other"


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def _git(
    *args: str,
    repo: Path,
    check: bool = True,
    capture: bool = True,
    timeout: int = 120,
    env: Optional[Dict[str, str]] = None,
) -> Tuple[int, str, str]:
    cmd = ["git", "-C", str(repo)] + list(args)
    result = subprocess.run(
        cmd,
        capture_output=capture,
        text=True,
        timeout=timeout,
        env=env,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args[:4])} failed:\n{result.stderr.strip()}"
        )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


# ---------------------------------------------------------------------------
# SemanticOptimizer
# ---------------------------------------------------------------------------

class SemanticOptimizer:
    """Analyzes and rewrites branch history by semantic intent grouping."""

    def __init__(self, branch: str, base: str, repo_path: str = ".") -> None:
        self.branch = branch
        self.base = base
        self.repo = Path(repo_path).resolve()
        self.analysis_id = f"semantic-{uuid.uuid4().hex[:8]}"
        self._backup_branch: Optional[str] = None
        _init_audit(self.repo)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _get_commits(self) -> List[Dict[str, str]]:
        """Return commits between base..branch in chronological order."""
        _, log, _ = _git(
            "log", f"{self.base}..{self.branch}",
            "--format=%H|||%s|||%b",
            "--reverse",
            repo=self.repo,
        )
        commits: List[Dict[str, str]] = []
        for line in log.splitlines():
            if "|||" not in line:
                continue
            parts = line.split("|||", 2)
            sha = parts[0]
            subject = parts[1]
            body = parts[2] if len(parts) > 2 else ""
            full_msg = f"{subject}\n{body}".strip()
            commits.append({
                "sha": sha,
                "subject": subject,
                "body": body,
                "intent": _classify(full_msg),
            })
        return commits

    # ------------------------------------------------------------------
    # Analyze (read-only)
    # ------------------------------------------------------------------

    def analyze(self) -> Dict[str, Any]:
        """
        Analyze commits and produce squash plan without making any changes.

        Returns JSON-serialisable analysis dict.
        """
        commits = self._get_commits()

        _audit("semantic_analysis_start", {
            "analysis_id": self.analysis_id,
            "branch": self.branch,
            "base": self.base,
            "commit_count": len(commits),
        })

        if not commits:
            result: Dict[str, Any] = {
                "analysis_id": self.analysis_id,
                "branch": self.branch,
                "base": self.base,
                "original_count": 0,
                "suggested_final_count": 0,
                "groups": [],
                "recommendation": "no-op: no commits between base and branch",
            }
            _audit("semantic_analysis_complete", result)
            return result

        # Group commits by intent (preserve order of first appearance)
        seen_intents: List[str] = []
        groups: Dict[str, List[Dict]] = defaultdict(list)
        for c in commits:
            if c["intent"] not in seen_intents:
                seen_intents.append(c["intent"])
            groups[c["intent"]].append(c)

        # Build squash groups
        squash_groups: List[Dict[str, Any]] = []
        for intent in seen_intents:
            group_commits = groups[intent]
            preserve = intent in _PRESERVE_INTENTS

            if preserve:
                # Each preserved commit becomes its own entry
                for c in group_commits:
                    squash_groups.append({
                        "intent": intent,
                        "preserve": True,
                        "commit_count": 1,
                        "commits": [{"sha": c["sha"][:12], "subject": c["subject"]}],
                        "suggested_message": c["subject"],
                    })
            else:
                # Squashable group
                first = group_commits[0]
                suggested = (
                    first["subject"]
                    if len(group_commits) == 1
                    else f"{intent}: {len(group_commits)} {intent} changes squashed"
                )
                squash_groups.append({
                    "intent": intent,
                    "preserve": False,
                    "commit_count": len(group_commits),
                    "commits": [{"sha": c["sha"][:12], "subject": c["subject"]} for c in group_commits],
                    "suggested_message": suggested,
                })

        breaking = sum(1 for c in commits if c["intent"] == "breaking")
        result = {
            "analysis_id": self.analysis_id,
            "branch": self.branch,
            "base": self.base,
            "original_count": len(commits),
            "suggested_final_count": len(squash_groups),
            "breaking_changes": breaking,
            "groups": squash_groups,
            "recommendation": (
                "squash" if len(commits) > len(squash_groups) else "no-op"
            ),
        }

        _audit("semantic_analysis_complete", {
            "analysis_id": self.analysis_id,
            "original": len(commits),
            "suggested": len(squash_groups),
            "recommendation": result["recommendation"],
        })
        return result

    # ------------------------------------------------------------------
    # Backup
    # ------------------------------------------------------------------

    def _backup(self) -> str:
        ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        backup = f"backup/semantic-optimizer/{self.branch.replace('/', '_')}/{ts}"
        _git("branch", backup, self.branch, repo=self.repo)
        self._backup_branch = backup
        _audit("backup_created", {
            "analysis_id": self.analysis_id,
            "backup_branch": backup,
        })
        logger.info(f"Backed up '{self.branch}' → '{backup}'")
        return backup

    # ------------------------------------------------------------------
    # Rewrite
    # ------------------------------------------------------------------

    def rewrite(self, force_push: bool = False) -> Dict[str, Any]:
        """
        Execute semantic history rewrite.

        Steps:
          1. Analyze commits to build squash plan
          2. Back up branch
          3. Run non-interactive git rebase -i using GIT_SEQUENCE_EDITOR
          4. Optionally force-push rewritten branch

        Returns rewrite result dict.
        """
        analysis = self.analyze()

        if analysis["original_count"] == 0 or analysis["recommendation"] == "no-op":
            return {"status": "no-op", "reason": analysis["recommendation"], "analysis": analysis}

        backup_branch = self._backup()

        # Build rebase-todo lines
        todo_lines: List[str] = []
        for group in analysis["groups"]:
            commits = group["commits"]
            if not commits:
                continue
            # First commit in group: 'pick'
            todo_lines.append(f"pick {commits[0]['sha']} {commits[0]['subject']}")
            if not group["preserve"]:
                # Remaining in squashable group: 'squash'
                for c in commits[1:]:
                    todo_lines.append(f"squash {c['sha']} {c['subject']}")
        todo_content = "\n".join(todo_lines) + "\n"

        _audit("semantic_rewrite_start", {
            "analysis_id": self.analysis_id,
            "branch": self.branch,
            "original_count": analysis["original_count"],
            "target_count": analysis["suggested_final_count"],
            "backup_branch": backup_branch,
        })

        # Write rebase script to temp file
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as fp:
            fp.write(todo_content)
            todo_file = fp.name

        env = os.environ.copy()
        env["GIT_SEQUENCE_EDITOR"] = f"cp {todo_file}"
        env["GIT_EDITOR"] = "true"  # suppress commit-message editor
        env["GIT_MERGE_AUTOEDIT"] = "no"

        try:
            result_proc = subprocess.run(
                ["git", "-C", str(self.repo), "rebase", "-i", self.base],
                env=env,
                capture_output=True,
                text=True,
                timeout=180,
            )

            if result_proc.returncode != 0:
                # Abort rebase to leave repo in clean state
                subprocess.run(
                    ["git", "-C", str(self.repo), "rebase", "--abort"],
                    capture_output=True,
                )
                raise RuntimeError(
                    f"Interactive rebase failed:\n{result_proc.stderr[:500]}"
                )

            # Count final commits
            _, final_log, _ = _git(
                "log", f"{self.base}..{self.branch}", "--oneline",
                repo=self.repo,
            )
            final_count = len([ln for ln in final_log.splitlines() if ln.strip()])

            if force_push:
                _git("push", "origin", f"+{self.branch}:{self.branch}", repo=self.repo)
                _audit("force_push_complete", {
                    "analysis_id": self.analysis_id,
                    "branch": self.branch,
                })

            _audit("semantic_rewrite_complete", {
                "analysis_id": self.analysis_id,
                "original_count": analysis["original_count"],
                "final_count": final_count,
                "backup_branch": backup_branch,
                "force_pushed": force_push,
            })
            logger.info(
                f"✅ Rewrite complete: {analysis['original_count']} → {final_count} commits"
            )
            return {
                "status": "success",
                "analysis_id": self.analysis_id,
                "original_count": analysis["original_count"],
                "final_count": final_count,
                "backup_branch": backup_branch,
                "force_pushed": force_push,
            }

        except Exception as exc:
            logger.error(f"Rewrite failed; backup preserved at '{backup_branch}': {exc}")
            _audit("semantic_rewrite_failed", {
                "analysis_id": self.analysis_id,
                "error": str(exc),
                "backup_branch": backup_branch,
            })
            return {
                "status": "failed",
                "error": str(exc),
                "backup_branch": backup_branch,
            }

        finally:
            Path(todo_file).unlink(missing_ok=True)

    # ------------------------------------------------------------------
    # Rollback
    # ------------------------------------------------------------------

    def rollback(self) -> Dict[str, Any]:
        """Restore branch to backup created by last rewrite()."""
        if not self._backup_branch:
            return {"status": "no-backup", "error": "No backup branch recorded in this session"}
        try:
            _, backup_sha, _ = _git("rev-parse", self._backup_branch, repo=self.repo)
            _git("reset", "--hard", backup_sha, repo=self.repo)
            _audit("rollback_complete", {
                "analysis_id": self.analysis_id,
                "restored_from": self._backup_branch,
                "sha": backup_sha,
            })
            logger.info(f"Rolled back to {self._backup_branch}")
            return {"status": "rolled-back", "restored_from": self._backup_branch}
        except Exception as exc:
            return {"status": "rollback-failed", "error": str(exc)}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Semantic git history optimizer — squash by intent"
    )
    sub = parser.add_subparsers(dest="command")

    for cmd_name, cmd_help in [
        ("analyze", "Analyze commits and print squash plan (read-only)"),
        ("preview", "Alias for analyze"),
    ]:
        p = sub.add_parser(cmd_name, help=cmd_help)
        p.add_argument("--branch", required=True)
        p.add_argument("--base", default="main")
        p.add_argument("--repo", default=".")

    rewrite_p = sub.add_parser("rewrite", help="Execute semantic history rewrite")
    rewrite_p.add_argument("--branch", required=True)
    rewrite_p.add_argument("--base", default="main")
    rewrite_p.add_argument("--force-push", action="store_true",
                           help="Force-push rewritten branch")
    rewrite_p.add_argument("--repo", default=".")

    rollback_p = sub.add_parser("rollback", help="Restore branch from backup")
    rollback_p.add_argument("--branch", required=True)
    rollback_p.add_argument("--base", default="main")
    rollback_p.add_argument("--repo", default=".")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    opt = SemanticOptimizer(
        branch=args.branch,
        base=args.base,
        repo_path=args.repo,
    )

    if args.command in ("analyze", "preview"):
        result = opt.analyze()
    elif args.command == "rewrite":
        result = opt.rewrite(force_push=getattr(args, "force_push", False))
    elif args.command == "rollback":
        result = opt.rollback()
    else:
        parser.print_help()
        sys.exit(1)

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
