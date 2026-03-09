"""Tests for credential manager and providers."""
import time
from unittest.mock import Mock, patch, MagicMock
from self_healing_orchestrator.credential_manager import CredentialManager, SecretProvider


class MockProvider(SecretProvider):
    def __init__(self):
        self.secrets = {}
    
    def get_secret(self, name: str) -> str:
        if name not in self.secrets:
            raise RuntimeError(f"Secret {name} not found")
        return self.secrets[name]
    
    def put_secret(self, name: str, value: str) -> None:
        self.secrets[name] = value
    
    def rotate_secret(self, name: str) -> str:
        return self.get_secret(name)


def test_credential_manager_caching():
    """Test that CredentialManager caches secrets with TTL."""
    mock_provider = MockProvider()
    mock_provider.put_secret("test-key", "test-value")
    
    # Create a manager with short TTL
    cm = CredentialManager(provider="vault", config={}, ttl=1)
    cm._provider = mock_provider
    
    # First get should cache
    result1 = cm.get("test-key")
    assert result1 == "test-value"
    
    # Change value in provider
    mock_provider.secrets["test-key"] = "new-value"
    
    # Should still return cached value
    result2 = cm.get("test-key")
    assert result2 == "test-value"
    
    # Wait for TTL to expire
    time.sleep(1.1)
    
    # Should now return new value
    result3 = cm.get("test-key")
    assert result3 == "new-value"


def test_credential_manager_put():
    """Test that CredentialManager stores secrets."""
    mock_provider = MockProvider()
    cm = CredentialManager(provider="vault", config={}, ttl=300)
    cm._provider = mock_provider
    
    cm.put("my-secret", "my-value")
    
    # Should be cached and retrievable
    assert cm.get("my-secret") == "my-value"
    assert mock_provider.get_secret("my-secret") == "my-value"


def test_credential_manager_rotate():
    """Test that CredentialManager rotates secrets."""
    mock_provider = MockProvider()
    mock_provider.put_secret("rotatable", "v1")
    
    cm = CredentialManager(provider="vault", config={}, ttl=300)
    cm._provider = mock_provider
    
    # Get current value
    assert cm.get("rotatable") == "v1"
    
    # Rotate (update in provider)
    mock_provider.put_secret("rotatable", "v2")
    new_value = cm.rotate("rotatable")
    
    # Should get rotated value
    assert new_value == "v2"
    assert cm.get("rotatable") == "v2"


@patch.dict("os.environ", {"VAULT_ADDR": "http://localhost:8200", "VAULT_TOKEN": "test-token"})
def test_vault_provider_init():
    """Test that VaultProvider initializes with env vars."""
    try:
        from self_healing_orchestrator.providers.vault_provider import VaultProvider
        provider = VaultProvider()
        assert provider.url == "http://localhost:8200"
        assert provider.token == "test-token"
    except ImportError:
        # requests not available
        pass


@patch.dict("os.environ", {"GCP_PROJECT_ID": "test-project"})
def test_gsm_provider_init():
    """Test that GoogleSecretManagerProvider initializes with env vars."""
    try:
        from self_healing_orchestrator.providers.gsm_provider import GoogleSecretManagerProvider
        provider = GoogleSecretManagerProvider()
        assert provider.project_id == "test-project"
    except ImportError:
        # google-cloud-secret-manager not available
        pass


@patch.dict("os.environ", {"AWS_REGION": "us-west-2"})
def test_aws_provider_init():
    """Test that AWSSecretsManagerProvider initializes with env vars."""
    try:
        from self_healing_orchestrator.providers.aws_provider import AWSSecretsManagerProvider
        provider = AWSSecretsManagerProvider()
        assert provider.region == "us-west-2"
    except ImportError:
        # boto3 not available
        pass


if __name__ == "__main__":
    test_credential_manager_caching()
    test_credential_manager_put()
    test_credential_manager_rotate()
    print("✓ All credential manager tests passed")
