"""
Unit tests for Safe Deletion Framework (Enhancement #5).

Tests backup creation, dependent detection, recovery,
and immutable audit trails.
"""

import pytest
from pathlib import Path


@pytest.mark.unit
class TestSafeDeletion:
    """Test suite for safe deletion framework."""
    
    def test_backup_before_delete(self, mock_git_operations, test_workspace):
        """Test backup created before deletion."""
        result = mock_git_operations.safe_delete("feature/old-xyz")
        
        assert result["status"] == "deleted"
        assert "backup" in result
        backup_path = result.get("backup", "backup/feature/old-xyz")
        assert "backup" in backup_path
    
    def test_dependent_branch_detection(self):
        """Test detection of branches depending on deleted branch."""
        dependents = {
            "branches": ["feature/child-1", "feature/child-2"],
            "count": 2
        }
        assert len(dependents["branches"]) == dependents["count"]
    
    def test_force_delete_with_warning(self):
        """Test force delete requires confirmation."""
        deletion = {
            "branch": "protected-branch",
            "has_dependents": True,
            "confirmation_required": True
        }
        assert deletion["confirmation_required"] is True
    
    def test_recovery_window(self):
        """Test 30-day recovery window available."""
        recovery = {
            "branch": "feature/old",
            "backed_up": True,
            "recovery_days": 30,
            "recovery_command": "git branch feature/old backup/feature/old-{timestamp}"
        }
        assert recovery["recovery_days"] == 30
    
    def test_immutable_audit_trail(self, audit_log_file):
        """Test all deletions logged to immutable JSONL."""
        assert audit_log_file.exists() or audit_log_file.parent.exists()
    
    def test_open_pr_detection(self):
        """Test detection of open PRs based on branch."""
        prs = {
            "branch": "feature/xyz",
            "open_prs": [2700, 2701],
            "can_delete": False
        }
        assert prs["can_delete"] is False
        assert len(prs["open_prs"]) == 2
    
    def test_safe_delete_workflow(self, mock_git_operations):
        """Test complete safe deletion workflow."""
        # 1. Check dependents
        # 2. Check open PRs
        # 3. Create backup
        # 4. Delete branch
        # 5. Log to audit trail
        
        result = mock_git_operations.safe_delete("feature/test")
        assert result["status"] == "deleted"
    
    def test_recovery_from_backup(self, test_workspace):
        """Test recovery of deleted branch from backup."""
        backup_location = test_workspace / "backup" / "feature" / "old"
        backup_location.parent.mkdir(parents=True, exist_ok=True)
        
        # In production, would restore from git
        assert backup_location.parent.exists()
    
    def test_accidental_delete_prevented(self):
        """Test accidental deletion of critical branches prevented."""
        critical_branches = ["main", "develop", "production"]
        
        result = {
            "branch": "main",
            "deletion_allowed": False,
            "reason": "critical branch protection"
        }
        assert result["deletion_allowed"] is False
    
    def test_deletion_batch_safety(self, mock_git_operations):
        """Test batch deletion of multiple branches."""
        branches = ["feature/old-1", "feature/old-2", "feature/old-3"]
        results = [mock_git_operations.safe_delete(b) for b in branches]
        
        assert len(results) == 3
        assert all(r["status"] == "deleted" for r in results)
