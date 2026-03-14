"""
Pytest configuration and shared fixtures for git-workflow test suite.
Provides mock repositories, credential managers, and common test utilities.
"""

import pytest
import tempfile
import shutil
import subprocess
import os
import json
from pathlib import Path
from datetime import datetime, timedelta


@pytest.fixture(scope="session")
def test_workspace():
    """Create temporary workspace for all tests."""
    workspace = tempfile.mkdtemp(prefix="git-workflow-tests-")
    yield workspace
    shutil.rmtree(workspace, ignore_errors=True)


@pytest.fixture
def git_repo(test_workspace):
    """Create a temporary git repository for testing."""
    repo_path = Path(test_workspace) / f"test-repo-{datetime.now().timestamp()}"
    repo_path.mkdir()
    
    # Initialize repo
    subprocess.run(["git", "init"], cwd=repo_path, capture_output=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo_path, capture_output=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo_path, capture_output=True)
    
    # Create initial commit
    (repo_path / "README.md").write_text("# Test Repository\n")
    subprocess.run(["git", "add", "README.md"], cwd=repo_path, capture_output=True)
    subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=repo_path, capture_output=True)
    
    yield repo_path
    shutil.rmtree(repo_path, ignore_errors=True)


@pytest.fixture
def mock_credential_manager(monkeypatch):
    """Mock credential manager for testing."""
    class MockCredentialManager:
        def get_github_token(self):
            """Return mock GitHub token."""
            return "ghp_mock_token_12345"
        
        def get_ssh_key(self, account="automation"):
            """Return mock SSH key."""
            return f"""-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA2vL8+2v8+2v8
-----END RSA PRIVATE KEY-----"""
        
        def get_vault_secret(self, path):
            """Return mock Vault secret."""
            return {"value": "mock_secret"}
        
        def cleanup(self):
            """Mock cleanup."""
            pass
    
    return MockCredentialManager()


@pytest.fixture
def mock_git_operations(monkeypatch):
    """Mock git operations for testing."""
    class MockGitOperations:
        def __init__(self):
            self.merge_results = []
            self.delete_results = []
        
        def merge_pr(self, pr_number):
            """Mock PR merge."""
            result = {"pr_number": pr_number, "status": "success", "sha": f"abc123{pr_number}"}
            self.merge_results.append(result)
            return result
        
        def check_conflicts(self, base, head):
            """Mock conflict detection."""
            return {"has_conflicts": False, "conflicts": []}
        
        def safe_delete(self, branch):
            """Mock safe deletion."""
            result = {"branch": branch, "status": "deleted", "backup": f"backup/{branch}"}
            self.delete_results.append(result)
            return result
    
    return MockGitOperations()


@pytest.fixture
def audit_log_file(test_workspace):
    """Create temporary audit log file."""
    log_file = Path(test_workspace) / "audit-trail.jsonl"
    log_file.touch()
    return log_file


@pytest.fixture
def metrics_database(test_workspace):
    """Create temporary metrics database."""
    db_file = Path(test_workspace) / "git-metrics.db"
    return db_file


def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line("markers", "unit: unit tests")
    config.addinivalue_line("markers", "integration: integration tests")
    config.addinivalue_line("markers", "performance: performance tests")
    config.addinivalue_line("markers", "security: security tests")
    config.addinivalue_line("markers", "resilience: failure/recovery tests")


@pytest.fixture
def performance_timer():
    """Measure performance of operations."""
    class PerformanceTimer:
        def __init__(self):
            self.start_time = None
            self.end_time = None
        
        def start(self):
            self.start_time = datetime.now()
        
        def stop(self):
            self.end_time = datetime.now()
            return self.duration_ms
        
        @property
        def duration_ms(self):
            if self.start_time and self.end_time:
                return int((self.end_time - self.start_time).total_seconds() * 1000)
            return None
    
    return PerformanceTimer()


@pytest.fixture
def mock_network():
    """Mock network operations for testing."""
    class MockNetwork:
        def __init__(self):
            self.requests = []
            self.fail_count = 0
        
        def make_request(self, url, method="GET"):
            """Mock HTTP request."""
            self.requests.append({"url": url, "method": method})
            
            if self.fail_count > 0:
                self.fail_count -= 1
                raise ConnectionError("Mock network failure")
            
            return {"status": 200, "body": "{}"}
        
        def set_failure_mode(self, count):
            """Set number of failures before success."""
            self.fail_count = count
    
    return MockNetwork()
