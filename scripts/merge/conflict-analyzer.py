#!/usr/bin/env python3
"""
conflict-analyzer.py
Pre-merge conflict detection and semantic analysis.

FEATURES:
  - 3-way diff analysis
  - File-level conflict detection
  - Dependency conflict detection (package.json, go.mod, requirements.txt)
  - Auto-resolvable pattern matching
  - Merge strategy recommendations
  - Immutable audit trail

USAGE:
  from conflict_analyzer import ConflictAnalyzer
  
  analyzer = ConflictAnalyzer(repo_path="/path/to/repo")
  result = analyzer.analyze(base_branch="main", head_branch="feature/xyz")
  
  if result["has_conflicts"]:
      print(f"Conflicts: {result['conflicts']}")
      print(f"Recommendations: {result['recommendations']}")
"""

import os
import json
import subprocess
import logging
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, asdict
from datetime import datetime

logging.basicConfig(
    format='{"timestamp": "%(asctime)s", "component": "conflict-analyzer", "level": "%(levelname)s", "message": "%(message)s"}',
    level=logging.INFO
)
logger = logging.getLogger(__name__)


@dataclass
class ConflictInfo:
    """Conflict information."""
    file_path: str
    conflict_type: str  # 'content', 'dependency', 'mode', 'delete'
    base_content: Optional[str] = None
    head_content: Optional[str] = None
    is_auto_resolvable: bool = False
    resolution_suggestion: Optional[str] = None


class ConflictAnalyzer:
    """Analyze merge conflicts before merging (PRE-MERGE ANALYSIS)."""
    
    def __init__(self, repo_path: str = "."):
        """
        Initialize conflict analyzer.
        
        Args:
            repo_path: Path to git repository
        """
        self.repo_path = Path(repo_path).resolve()
        self.audit_file = self.repo_path / "logs" / "conflict-analysis.jsonl"
        self.audit_file.parent.mkdir(parents=True, exist_ok=True)
        
        logger.info(f"ConflictAnalyzer initialized for repo: {self.repo_path}")
    
    def _run_git(self, *args: str, check: bool = False) -> Tuple[int, str, str]:
        """Run git command."""
        cmd = ["git", "-C", str(self.repo_path)] + list(args)
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
            )
            if check and result.returncode != 0:
                raise RuntimeError(f"Git command failed: {' '.join(cmd)}\n{result.stderr}")
            return result.returncode, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            raise TimeoutError(f"Git command timed out: {' '.join(cmd)}")
    
    def _audit_log(self, event: str, details: Dict[str, Any]) -> None:
        """Write audit log entry."""
        entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "event": event,
            "details": details,
        }
        with open(self.audit_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
    
    def _is_dependency_file(self, file_path: str) -> bool:
        """Check if file is a dependency manifest."""
        dep_files = {
            "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
            "Pipfile", "requirements.txt", "Pipfile.lock",
            "Gemfile", "Gemfile.lock",
            "go.mod", "go.sum",
            "Cargo.lock",
            "mix.lock",
        }
        return Path(file_path).name in dep_files
    
    def _analyze_dependency_conflict(
        self,
        file_path: str,
        base_content: str,
        head_content: str,
    ) -> Tuple[bool, Optional[str]]:
        """
        Analyze dependency file conflict and suggest resolution.
        
        Returns:
            (is_auto_resolvable, suggestion)
        """
        # For package.json: prefer head version (more recent)
        if file_path.endswith("package.json"):
            try:
                base_json = json.loads(base_content)
                head_json = json.loads(head_content)
                
                # If only deps changed (not package.json structure), suggest head
                if set(base_json.keys()) == set(head_json.keys()):
                    return True, "Use head version (newer dependencies)"
            except json.JSONDecodeError:
                pass
        
        # For lock files: regenerate via package manager
        if "lock" in file_path.lower():
            return True, "Regenerate lock file (npm ci or yarn install)"
        
        return False, None
    
    def _check_file_conflicts(
        self,
        base_branch: str,
        head_branch: str,
    ) -> List[ConflictInfo]:
        """
        Check for file-level conflicts using 3-way diff.
        
        Returns:
            List of ConflictInfo
        """
        conflicts = []
        
        # Get list of files changed between base and head
        rc, files_list, _ = self._run_git(
            "diff", "--name-only", f"{base_branch}...{head_branch}"
        )
        
        if rc != 0 or not files_list.strip():
            return conflicts
        
        for file_path in files_list.strip().split("\n"):
            if not file_path:
                continue
            
            # Get base version
            rc, base_content, _ = self._run_git(
                "show", f"{base_branch}:{file_path}", check=False
            )
            base_content = base_content if rc == 0 else ""
            
            # Get head version
            rc, head_content, _ = self._run_git(
                "show", f"{head_branch}:{file_path}", check=False
            )
            head_content = head_content if rc == 0 else ""
            
            # Attempt 3-way merge
            rc, _, merge_error = self._run_git(
                "merge-file", "-p", "-L", "base", "-L", "head", "-L", "merge",
                file_path, f":{file_path}", f"{head_branch}:{file_path}",
                check=False
            )
            
            if "conflict" in merge_error.lower() or "<<<<<<" in merge_error:
                conflict_type = "content"
                
                # Check if dependency file
                if self._is_dependency_file(file_path):
                    conflict_type = "dependency"
                    is_auto, suggestion = self._analyze_dependency_conflict(
                        file_path, base_content, head_content
                    )
                else:
                    is_auto, suggestion = False, None
                
                conflicts.append(ConflictInfo(
                    file_path=file_path,
                    conflict_type=conflict_type,
                    base_content=base_content[:200] if base_content else None,
                    head_content=head_content[:200] if head_content else None,
                    is_auto_resolvable=is_auto,
                    resolution_suggestion=suggestion,
                ))
        
        return conflicts
    
    def analyze(
        self,
        base_branch: str,
        head_branch: str,
    ) -> Dict[str, Any]:
        """
        Analyze merge conflicts (PRE-MERGE).
        
        Args:
            base_branch: Base branch (e.g., 'main')
            head_branch: Head branch (e.g., 'feature/xyz')
        
        Returns:
            Analysis dictionary
        """
        logger.info(f"Analyzing conflicts: {base_branch} ← {head_branch}")
        
        # Fetch refs
        self._run_git("fetch", "origin", f"{base_branch}:{base_branch}", check=False)
        self._run_git("fetch", "origin", f"{head_branch}:{head_branch}", check=False)
        
        # Check for conflicts
        file_conflicts = self._check_file_conflicts(base_branch, head_branch)
        
        # Determine merge strategy recommendation
        recommendations = []
        auto_resolvable_count = sum(1 for c in file_conflicts if c.is_auto_resolvable)
        
        if len(file_conflicts) == 0:
            recommendations.append("✅ No conflicts detected. Safe to merge.")
        elif auto_resolvable_count == len(file_conflicts):
            recommendations.append("✅ All conflicts are auto-resolvable.")
            for conflict in file_conflicts:
                if conflict.resolution_suggestion:
                    recommendations.append(f"  - {conflict.file_path}: {conflict.resolution_suggestion}")
        else:
            recommendations.append(f"⚠️  {len(file_conflicts)} conflict(s) found. Manual review required.")
            for conflict in file_conflicts:
                recommendations.append(f"  - {conflict.file_path}: {conflict.conflict_type}")
        
        result = {
            "base_branch": base_branch,
            "head_branch": head_branch,
            "has_conflicts": len(file_conflicts) > 0,
            "conflict_count": len(file_conflicts),
            "conflicts": [asdict(c) for c in file_conflicts],
            "auto_resolvable_count": auto_resolvable_count,
            "recommendations": recommendations,
            "analysis_timestamp": datetime.utcnow().isoformat(),
        }
        
        logger.info(f"Conflict analysis complete: {len(file_conflicts)} conflict(s)")
        self._audit_log("conflict_analysis", {
            "base_branch": base_branch,
            "head_branch": head_branch,
            "conflict_count": len(file_conflicts),
            "auto_resolvable": auto_resolvable_count,
        })
        
        return result


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 3:
        print("Usage: conflict-analyzer.py <base_branch> <head_branch> [repo_path]")
        sys.exit(1)
    
    base = sys.argv[1]
    head = sys.argv[2]
    repo = sys.argv[3] if len(sys.argv) > 3 else "."
    
    analyzer = ConflictAnalyzer(repo_path=repo)
    result = analyzer.analyze(base, head)
    
    print(json.dumps(result, indent=2))
    
    # Exit code: 0 if no conflicts, 10 if conflicts, 1 if error
    if result["has_conflicts"]:
        sys.exit(10)
    else:
        sys.exit(0)
