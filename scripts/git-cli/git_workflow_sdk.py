#!/usr/bin/env python3
"""
git_workflow_sdk.py
Simple, discoverable Python SDK for all git operations.

USAGE:
  from git_workflow import Workflow
  
  wf = Workflow(repo=\"./self-hosted-runner\")
  
  # Merge batch of PRs (returns JSON-serializable result)
  result = wf.merge_prs([2709, 2716], protection_mode=\"strict\")
  print(f\"Merged: {result['merged']}, Failed: {result['failed']}\")
  
  # View metrics
  metrics = wf.get_metrics()
  print(f\"Success rate: {metrics['merge_success_rate']}%\")
  
  # Safe delete with context manager
  with Workflow(repo=\".\") as wf:
      wf.safe_delete(\"feature/xyz\", backup=True)
      # Auto-cleanup on exit
"""

import sys
from pathlib import Path
from typing import List, Dict, Any, Optional
import json

# Add parent scripts directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth.credential_manager import CredentialManager
from git_cli.git_workflow import GitWorkflow


class Workflow:
    """
    High-level API for git operations.
    
    Simple, discoverable interface with:
      - Type hints (mypy compatible)
      - Comprehensive docstrings
      - JSON-serializable results
      - Context manager support
    """
    
    def __init__(self, repo: str = "."):
        """
        Initialize workflow engine.
        
        Args:
            repo: Repository path (default: current directory)
        
        Example:
            wf = Workflow(repo=\"./self-hosted-runner\")
        """
        self.repo = repo
        self._cred_manager = CredentialManager()
        self._git_workflow = GitWorkflow(repo_path=repo, cred_manager=self._cred_manager)
    
    def merge_prs(
        self,
        pr_numbers: List[int],
        max_parallel: int = 5,
        method: str = "merge",
        protection_mode: str = "strict",
    ) -> Dict[str, Any]:
        """
        Merge multiple PRs in parallel.
        
        Args:
            pr_numbers: List of PR numbers (e.g., [2709, 2716])
            max_parallel: Max concurrent merges (1-10, default: 5)
            method: Merge method ('merge', 'squash', 'rebase', default: 'merge')
            protection_mode: Branch protection mode ('strict', 'bypass', default: 'strict')
        
        Returns:
            Dictionary with merge results:
            {
                'merged': int,  # Count of successful merges
                'failed': int,  # Count of failed merges
                'total': int,   # Total PRs
                'results': List[Dict],  # Per-PR details
                'duration_seconds': float,
            }
        
        Example:
            result = wf.merge_prs([2709, 2716], max_parallel=5)
            print(f\"Merged: {result['merged']}, Failed: {result['failed']}\")
        """
        protect = protection_mode == "strict"
        results = self._git_workflow.merge_batch(
            pr_numbers,
            max_parallel=max_parallel,
            method=method,
            protect_branches=protect,
        )
        
        merged = sum(1 for r in results if r.get("status") == "merged")
        failed = sum(1 for r in results if r.get("status") != "merged")
        
        return {
            "merged": merged,
            "failed": failed,
            "total": len(pr_numbers),
            "results": results,
        }
    
    def safe_delete(self, branch: str, backup: bool = True) -> Dict[str, Any]:
        """
        Safely delete a branch with backup.
        
        Args:
            branch: Branch name (e.g., 'feature/xyz')
            backup: Create backup before deletion (default: True)
        
        Returns:
            Dictionary with deletion result:
            {
                'branch': str,
                'status': 'deleted',
                'backup_created': bool,
                'dependents': List[str],
            }
        
        Example:
            result = wf.safe_delete(\"feature/old\", backup=True)
            print(f\"Deleted: {result['branch']}, Backup: {result['backup_created']}\")
        """
        return self._git_workflow.safe_delete(branch, backup=backup)
    
    def get_status(self) -> Dict[str, Any]:
        """
        Get current git workflow status.
        
        Returns:
            Dictionary with status:
            {
                'repo': str,
                'recent_commits': List[str],
                'branches': List[str],
                'audit_entries': int,
            }
        
        Example:
            status = wf.get_status()
            print(f\"Commits: {len(status['recent_commits'])}\")
        """
        return self._git_workflow.get_status()
    
    def get_metrics(self) -> Dict[str, Any]:
        """
        Get git workflow metrics (last 7 days).
        
        Returns:
            Dictionary with metrics:
            {
                'merge_success_rate': float,  # Percentage
                'avg_merge_duration': float,  # Seconds
                'conflict_rate': float,  # Percentage
                'commits_per_day': float,
                'timestamp': str,  # ISO 8601
            }
        
        Example:
            metrics = wf.get_metrics()
            print(f\"Success rate: {metrics['merge_success_rate']}%\")
            print(f\"Avg merge time: {metrics['avg_merge_duration']}s\")
        """
        from git_cli.observability.git_metrics import GitMetrics
        
        metrics = GitMetrics(repo_path=self.repo)
        return metrics.collect()
    
    def get_audit_log(self, since_hours: int = 24) -> List[Dict[str, Any]]:
        """
        Get immutable audit log (last N hours).
        
        Args:
            since_hours: Include events from last N hours (default: 24)
        
        Returns:
            List of audit entries (JSONL format)
        
        Example:
            log = wf.get_audit_log(since_hours=24)
            for entry in log:
                print(f\"{entry['timestamp']}: {entry['event']}\")
        """
        audit_file = Path(self.repo) / "logs" / "git-workflow-audit.jsonl"
        if not audit_file.exists():
            return []
        
        from datetime import datetime, timedelta
        cutoff = datetime.utcnow() - timedelta(hours=since_hours)
        
        entries = []
        with open(audit_file) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    ts = datetime.fromisoformat(entry.get("timestamp", ""))
                    if ts >= cutoff:
                        entries.append(entry)
                except:
                    pass
        
        return entries
    
    def cleanup(self) -> None:
        """Clean up ephemeral resources (credentials, temp files)."""
        self._cred_manager.cleanup()
    
    def __enter__(self):
        """Context manager entry."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit (auto-cleanup)."""
        self.cleanup()
    
    def __repr__(self) -> str:
        """String representation."""
        return f"Workflow(repo={self.repo})"


if __name__ == "__main__":
    # Example usage
    import argparse
    
    parser = argparse.ArgumentParser(description="Git workflow SDK")
    parser.add_argument("--repo", default=".", help="Repository path")
    parser.add_argument("action", choices=["status", "metrics", "help"], help="Action")
    
    args = parser.parse_args()
    
    with Workflow(repo=args.repo) as wf:
        if args.action == "status":
            status = wf.get_status()
            print(json.dumps(status, indent=2))
        elif args.action == "metrics":
            metrics = wf.get_metrics()
            print(json.dumps(metrics, indent=2))
        elif args.action == "help":
            print(__doc__)
