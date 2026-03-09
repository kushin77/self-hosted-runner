#!/usr/bin/env python3
"""
Test Suite for Ephemeral Lifecycle Controller

Tests for:
- TTL policy matching
- TTL calculation with telemetry adjustments
- Graceful drain operations
- Safe reap verification
- Audit logging
"""

import unittest
import tempfile
import json
import yaml
from pathlib import Path
from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock, mock_open
import sys
import os

# Add scripts directory to path
sys.path.insert(0, str(Path(__file__).parent))

from ephemeral_lifecycle_controller import (
    EphemeralLifecycleController,
    DrainStrategy,
    TTLConfig
)


class TestTTLPolicyMatching(unittest.TestCase):
    """Tests for TTL policy matching"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.config_path = Path(self.temp_dir.name) / "policy.yaml"
        self._create_test_config()

    def tearDown(self):
        """Cleanup"""
        self.temp_dir.cleanup()

    def _create_test_config(self):
        """Create test policy configuration"""
        config = {
            "global": {
                "default_ttl": 1800,
                "max_ttl": 86400,
                "min_ttl": 300
            },
            "policies": [
                {
                    "name": "quick-test",
                    "filters": {
                        "job_type": ["test", "lint"],
                        "max_duration": 300
                    },
                    "ttl_config": {
                        "base_ttl": 600,
                        "max_ttl": 900,
                        "complexity_multiplier": 1.0
                    }
                },
                {
                    "name": "build",
                    "filters": {
                        "job_type": ["build"],
                        "max_duration": 3600
                    },
                    "ttl_config": {
                        "base_ttl": 1800,
                        "max_ttl": 3600,
                        "complexity_multiplier": 1.5
                    }
                }
            ],
            "audit": {"enabled": False}
        }
        
        with open(self.config_path, 'w') as f:
            yaml.dump(config, f)

    def test_policy_matching_by_job_type(self):
        """Test matching policy by job type"""
        with patch.dict(os.environ, {"RUNNER_TEMP": self.temp_dir.name}):
            controller = EphemeralLifecycleController(str(self.config_path))
            
            policy = controller._match_policy("test")
            self.assertIsNotNone(policy)
            self.assertEqual(policy["name"], "quick-test")
            
            policy = controller._match_policy("build")
            self.assertIsNotNone(policy)
            self.assertEqual(policy["name"], "build")

    def test_policy_matching_no_match(self):
        """Test when policy doesn't match"""
        with patch.dict(os.environ, {"RUNNER_TEMP": self.temp_dir.name}):
            controller = EphemeralLifecycleController(str(self.config_path))
            
            policy = controller._match_policy("unknown")
            self.assertIsNone(policy)


class TestTTLCalculation(unittest.TestCase):
    """Tests for TTL calculation"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.config_path = Path(self.temp_dir.name) / "policy.yaml"
        self._create_test_config()

    def tearDown(self):
        """Cleanup"""
        self.temp_dir.cleanup()

    def _create_test_config(self):
        """Create test policy configuration"""
        config = {
            "global": {
                "default_ttl": 1800,
                "max_ttl": 86400,
                "min_ttl": 300
            },
            "policies": [
                {
                    "name": "test",
                    "filters": {"job_type": ["test"]},
                    "ttl_config": {
                        "base_ttl": 600,
                        "max_ttl": 900,
                        "complexity_multiplier": 1.0
                    }
                }
            ],
            "telemetry_adjustments": {
                "cpu_utilization": {
                    "high": 1.5,  # >80%
                    "medium": 1.2,  # 50-80%
                    "low": 0.8  # <50%
                },
                "memory_utilization": {
                    "high": 1.3,
                    "medium": 1.0,
                    "low": 0.9
                }
            },
            "audit": {"enabled": False}
        }
        
        with open(self.config_path, 'w') as f:
            yaml.dump(config, f)

    def test_ttl_base_calculation(self):
        """Test basic TTL calculation"""
        with patch.dict(os.environ, {"RUNNER_TEMP": self.temp_dir.name}):
            controller = EphemeralLifecycleController(str(self.config_path))
            
            policy = {
                "ttl_config": {
                    "base_ttl": 600,
                    "max_ttl": 900,
                    "complexity_multiplier": 2.0
                }
            }
            
            ttl = controller._calculate_ttl(policy)
            # 600 * 2.0 = 1200, capped at 900
            self.assertEqual(ttl, 900)

    def test_ttl_with_telemetry(self):
        """Test TTL calculation with telemetry"""
        with patch.dict(os.environ, {"RUNNER_TEMP": self.temp_dir.name}):
            controller = EphemeralLifecycleController(str(self.config_path))
            
            policy = {
                "ttl_config": {
                    "base_ttl": 600,
                    "max_ttl": 900,
                    "complexity_multiplier": 1.0
                }
            }
            
            telemetry = {
                "cpu_utilization": 0.9,  # High
                "memory_utilization": 0.6  # Medium
            }
            
            ttl = controller._calculate_ttl(policy, telemetry)
            # 600 * 1.0 * 1.5 (high cpu) * 1.0 (medium mem) = 900
            self.assertEqual(ttl, 900)


class TestAuditLogging(unittest.TestCase):
    """Tests for audit logging"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.config_path = Path(self.temp_dir.name) / "policy.yaml"
        
        config = {
            "global": {"default_ttl": 1800},
            "policies": [],
            "audit": {"enabled": True}
        }
        
        with open(self.config_path, 'w') as f:
            yaml.dump(config, f)

    def tearDown(self):
        """Cleanup"""
        self.temp_dir.cleanup()

    def test_audit_log_creation(self):
        """Test that audit logs are created"""
        with patch.dict(os.environ, {"RUNNER_TEMP": self.temp_dir.name}):
            controller = EphemeralLifecycleController(str(self.config_path))
            
            controller._audit_log("test_event", {"key": "value"})
            
            # Check that audit log file was created
            audit_dir = Path(self.temp_dir.name) / "audit-logs"
            log_files = list(audit_dir.glob("*.jsonl"))
            
            self.assertEqual(len(log_files), 1)
            
            # Check log content
            with open(log_files[0], 'r') as f:
                entry = json.loads(f.readline())
                self.assertEqual(entry["event"], "test_event")
                self.assertEqual(entry["details"]["key"], "value")


class TestDrainOperations(unittest.TestCase):
    """Tests for drain operations"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.config_path = Path(self.temp_dir.name) / "policy.yaml"
        
        config = {
            "global": {"default_ttl": 1800},
            "policies": [],
            "audit": {"enabled": False}
        }
        
        with open(self.config_path, 'w') as f:
            yaml.dump(config, f)

    def tearDown(self):
        """Cleanup"""
        self.temp_dir.cleanup()

    @patch('scripts.ephemeral_lifecycle_controller.subprocess.run')
    @patch('scripts.ephemeral_lifecycle_controller.psutil.process_iter')
    def test_graceful_drain_success(self, mock_process_iter, mock_subprocess):
        """Test successful graceful drain"""
        mock_process_iter.return_value = []  # No processes running
        mock_subprocess.return_value = MagicMock(returncode=0)
        
        with patch.dict(os.environ, {"RUNNER_TEMP": self.temp_dir.name, "GITHUB_ENV": ""}):
            controller = EphemeralLifecycleController(str(self.config_path))
            
            with patch.dict(os.environ, {"GITHUB_ENV": ""}):
                success = controller._graceful_drain(timeout=10)
            
            self.assertTrue(success)

    @patch('scripts.ephemeral_lifecycle_controller.subprocess.run')
    @patch('scripts.ephemeral_lifecycle_controller.psutil.process_iter')
    def test_graceful_drain_with_timeout(self, mock_process_iter, mock_subprocess):
        """Test graceful drain times out waiting for jobs"""
        mock_process_iter.return_value = [MagicMock(info={"pid": 1})]  # Process running
        mock_subprocess.return_value = MagicMock(returncode=0)
        
        with patch.dict(os.environ, {"RUNNER_TEMP": self.temp_dir.name}):
            controller = EphemeralLifecycleController(str(self.config_path))
            
            start = datetime.utcnow()
            success = controller._graceful_drain(timeout=2)
            elapsed = (datetime.utcnow() - start).total_seconds()
            
            # Should timeout after ~2 seconds
            self.assertGreaterEqual(elapsed, 2)


class TestReapOperations(unittest.TestCase):
    """Tests for reap operations"""

    def setUp(self):
        """Setup test fixtures"""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.config_path = Path(self.temp_dir.name) / "policy.yaml"
        
        config = {
            "global": {"default_ttl": 1800},
            "policies": [],
            "audit": {"enabled": False}
        }
        
        with open(self.config_path, 'w') as f:
            yaml.dump(config, f)

    def tearDown(self):
        """Cleanup"""
        self.temp_dir.cleanup()

    def test_check_reap_not_safe(self):
        """Test reap check when TTL not expired"""
        with patch.dict(os.environ, {"RUNNER_TEMP": self.temp_dir.name}):
            controller = EphemeralLifecycleController(str(self.config_path))
            
            # Create state with future TTL expiry
            state = {
                "assigned_at": datetime.utcnow().isoformat() + "Z",
                "ttl_assigned": 3600
            }
            controller._save_state(state)
            
            safe, checks = controller.check_reap()
            
            self.assertFalse(safe)
            self.assertFalse(checks["ttl_expired"])

    @patch('scripts.ephemeral_lifecycle_controller.psutil.process_iter')
    def test_check_reap_safe(self, mock_process_iter):
        """Test reap check when safe to reap"""
        mock_process_iter.return_value = []  # No processes
        
        with patch.dict(os.environ, {"RUNNER_TEMP": self.temp_dir.name}):
            controller = EphemeralLifecycleController(str(self.config_path))
            
            # Create state with expired TTL
            past_time = datetime.utcnow() - timedelta(seconds=3600)
            state = {
                "assigned_at": past_time.isoformat() + "Z",
                "ttl_assigned": 1800
            }
            controller._save_state(state)
            
            safe, checks = controller.check_reap()
            
            self.assertTrue(checks["ttl_expired"])
            self.assertTrue(checks["no_in_progress_jobs"])


def run_tests():
    """Run all tests"""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    # Add test classes
    suite.addTests(loader.loadTestsFromTestCase(TestTTLPolicyMatching))
    suite.addTests(loader.loadTestsFromTestCase(TestTTLCalculation))
    suite.addTests(loader.loadTestsFromTestCase(TestAuditLogging))
    suite.addTests(loader.loadTestsFromTestCase(TestDrainOperations))
    suite.addTests(loader.loadTestsFromTestCase(TestReapOperations))
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(run_tests())
