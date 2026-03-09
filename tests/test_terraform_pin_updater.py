"""
Integration tests for terraform_pin_updater.py
Purpose: Verify image pinning automation works correctly
"""

import json
import pytest
import tempfile
import subprocess
from pathlib import Path
from scripts.terraform_pin_updater import TerraformImagePinner


@pytest.fixture
def temp_repo():
    """Create temporary repo structure for testing"""
    with tempfile.TemporaryDirectory() as tmpdir:
        repo = Path(tmpdir)
        
        # Create directory structure
        (repo / "logs").mkdir()
        (repo / "terraform" / "environments" / "dev").mkdir(parents=True)
        (repo / "terraform" / "environments" / "staging").mkdir(parents=True)
        
        # Initialize git repo
        subprocess.run(["git", "init"], cwd=repo, capture_output=True, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, capture_output=True, check=True)
        subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo, capture_output=True, check=True)
        
        yield repo


@pytest.fixture
def pinner(temp_repo):
    """Create TerraformImagePinner instance"""
    return TerraformImagePinner(str(temp_repo))


class TestTrivyParsing:
    """Test Trivy output parsing"""
    
    def test_parse_trivy_approved_images(self, pinner):
        """Test parsing approved images (no critical vulns)"""
        trivy_json = json.dumps({
            "Results": [
                {
                    "Target": "ghcr.io/p4/vault-agent:1.16",
                    "Type": "image",
                    "Vulnerabilities": [
                        {"Severity": "LOW"},
                        {"Severity": "MEDIUM"}
                    ],
                    "Metadata": {
                        "ImageID": {"ID": "sha256:abc123def456"}
                    }
                }
            ]
        })
        
        result = pinner.parse_trivy_output(trivy_json)
        
        assert "ghcr.io/p4/vault-agent:1.16" in result
        assert result["ghcr.io/p4/vault-agent:1.16"] == "sha256:abc123def456"
    
    def test_parse_trivy_blocked_images(self, pinner):
        """Test rejection of images with critical vulnerabilities"""
        trivy_json = json.dumps({
            "Results": [
                {
                    "Target": "ghcr.io/p4/runner:latest",
                    "Type": "image",
                    "Vulnerabilities": [
                        {"Severity": "CRITICAL"},
                        {"Severity": "HIGH"}
                    ],
                    "Metadata": {
                        "ImageID": {"ID": "sha256:blocked123"}
                    }
                }
            ]
        })
        
        result = pinner.parse_trivy_output(trivy_json)
        
        # Critical vuln image should be rejected
        assert "ghcr.io/p4/runner:latest" not in result
    
    def test_parse_trivy_invalid_json(self, pinner):
        """Test handling of invalid JSON"""
        with pytest.raises(ValueError):
            pinner.parse_trivy_output("invalid json")
    
    def test_parse_trivy_empty_results(self, pinner):
        """Test handling of empty results"""
        trivy_json = json.dumps({"Results": []})
        result = pinner.parse_trivy_output(trivy_json)
        assert result == {}


class TestTerraformUpdate:
    """Test Terraform file updates"""
    
    def test_update_terraform_pins(self, pinner, temp_repo):
        """Test updating Terraform files with pins"""
        # Create test terraform file
        tf_content = '''
resource "google_compute_instance_template" "runner" {
  name = "runner-template"
  
  container_image = "ghcr.io/p4/vault-agent:1.16"
  image_ref       = "ghcr.io/p4/runner:latest"
}
'''
        tf_file = temp_repo / "terraform" / "environments" / "dev" / "main.tf"
        tf_file.write_text(tf_content)
        
        # Update with pins
        image_pins = {
            "ghcr.io/p4/vault-agent:1.16": "sha256:vault123",
            "ghcr.io/p4/runner:latest": "sha256:runner456"
        }
        
        results = pinner.update_terraform_pins([tf_file], image_pins)
        
        # Verify results
        assert str(tf_file) in results
        updated_content = tf_file.read_text()
        
        # Verify pins were added
        assert "ghcr.io/p4/vault-agent:1.16@sha256:vault123" in updated_content
        assert "ghcr.io/p4/runner:latest@sha256:runner456" in updated_content
    
    def test_update_terraform_idempotent(self, pinner, temp_repo):
        """Test that updates are idempotent"""
        tf_file = temp_repo / "terraform" / "environments" / "dev" / "main.tf"
        original_content = 'image = "ghcr.io/p4/vault:1.0@sha256:abc123"'
        tf_file.write_text(original_content)
        
        # Try to update with same pin
        image_pins = {"ghcr.io/p4/vault:1.0": "sha256:abc123"}
        
        pinner.update_terraform_pins([tf_file], image_pins)
        
        # Content should be unchanged
        assert tf_file.read_text() == original_content
    
    def test_update_nonexistent_file(self, pinner):
        """Test handling of nonexistent file"""
        nonexistent = Path("/tmp/nonexistent-12345.tf")
        
        result = pinner.update_terraform_pins([nonexistent], {})
        
        # Should gracefully skip
        assert len(result) == 0


class TestAuditLog:
    """Test immutable audit logging"""
    
    def test_audit_log_append_only(self, pinner):
        """Test audit log is append-only"""
        pinner.audit_log("test_action", "success", "test details")
        
        content1 = pinner.audit_log_path.read_text()
        assert "test_action" in content1
        
        # Append another entry
        pinner.audit_log("test_action2", "success", "more details")
        
        content2 = pinner.audit_log_path.read_text()
        
        # Previous entry should still be there
        assert "test_action" in content2
        assert "test_action2" in content2
        assert content2.startswith(content1)
    
    def test_audit_log_valid_json(self, pinner):
        """Test audit log entries are valid JSON"""
        pinner.audit_log("test", "success", "details")
        
        with open(pinner.audit_log_path) as f:
            for line in f:
                entry = json.loads(line)
                assert "timestamp" in entry
                assert "action" in entry
                assert "status" in entry


class TestE2EWorkflow:
    """End-to-end workflow tests"""
    
    def test_e2e_scan_to_pin(self, pinner, temp_repo):
        """Test complete workflow: parse trivy → update terraform → validate"""
        # Step 1: Create test terraform file
        tf_file = temp_repo / "terraform" / "environments" / "staging" / "main.tf"
        tf_file.write_text('''
variable "images" {
  default = {
    vault   = "vault:1.16"
    runner  = "runner:v2"
  }
}

resource "template" "runner" {
  vault_image  = var.images["vault"]
  runner_image = var.images["runner"]
}
''')
        
        # Step 2: Parse Trivy output
        trivy_output = json.dumps({
            "Results": [
                {
                    "Target": "vault:1.16",
                    "Vulnerabilities": [],
                    "Metadata": {"ImageID": {"ID": "sha256:vault_digest"}}
                },
                {
                    "Target": "runner:v2",
                    "Vulnerabilities": [{"Severity": "MEDIUM"}],
                    "Metadata": {"ImageID": {"ID": "sha256:runner_digest"}}
                }
            ]
        })
        
        approved_images = pinner.parse_trivy_output(trivy_output)
        
        # Should only have vault (runner has vuln)
        assert "vault:1.16" in approved_images
        assert "runner:v2" not in approved_images
        
        # Step 3: Update terraform
        updates = pinner.update_terraform_pins([tf_file], approved_images)
        
        # Should have been updated
        assert str(tf_file) in updates
        
        # Step 4: Verify update
        content = tf_file.read_text()
        assert "vault:1.16@sha256:vault_digest" in content
    
    def test_e2e_orchestration_idempotent(self, pinner, temp_repo):
        """Test that running orchestration twice is safe (idempotent)"""
        tf_file = temp_repo / "terraform" / "environments" / "dev" / "main.tf"
        tf_file.write_text('image = "test:v1"')
        
        pins = {"test:v1": "sha256:digest123"}
        
        # First run
        result1 = pinner.update_terraform_pins([tf_file], pins)
        content1 = tf_file.read_text()
        
        # Second run
        result2 = pinner.update_terraform_pins([tf_file], pins)
        content2 = tf_file.read_text()
        
        # Both should produce same result
        assert content1 == content2
        assert tf_file.read_text() == 'image = "test:v1@sha256:digest123"'


class TestRollback:
    """Test error handling and rollback"""
    
    def test_rollback_on_syntax_error(self, pinner, temp_repo):
        """Test that invalid updates don't break terraform"""
        tf_file = temp_repo / "terraform" / "environments" / "dev" / "main.tf"
        original_content = 'resource "test" "name" {\n  value = "original"\n}'
        tf_file.write_text(original_content)
        
        # Update should not corrupt syntax
        pins = {"image:v1": "sha256:deadbeef"}
        pinner.update_terraform_pins([tf_file], pins)
        
        # File should not be corrupted
        updated = tf_file.read_text()
        assert "resource" in updated  # Structure preserved


class TestIntegration:
    """Integration with git and GitHub"""
    
    def test_git_commit_changes(self, pinner, temp_repo):
        """Test that changes can be committed"""
        tf_file = temp_repo / "terraform" / "environments" / "dev" / "main.tf"
        tf_file.write_text('image = "test:v1"')
        
        # Stage and commit
        subprocess.run(["git", "add", "."], cwd=temp_repo, check=True, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "initial"],
            cwd=temp_repo,
            capture_output=True,
            check=True
        )
        
        # Make update
        pinner.update_terraform_pins([tf_file], {"test:v1": "sha256:abc"})
        
        # Verify file is modified
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=temp_repo,
            capture_output=True,
            text=True
        )
        
        assert "main.tf" in result.stdout


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
