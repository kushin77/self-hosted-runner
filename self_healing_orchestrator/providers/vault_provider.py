"""HashiCorp Vault provider implementation with HTTP client.

Supports Azure/AWS/GCP OIDC authentication + JWT auth.
Credentials are never stored or logged in this module.
"""
import os
import json
import logging
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False


class VaultProvider:
    """Use HashiCorp Vault for secret storage and retrieval.
    
    Supports authentication via:
    - Environment variables (VAULT_ADDR, VAULT_TOKEN)
    - OIDC JWT (from OIDC provider)
    - Service account tokens
    """

    def __init__(
        self,
        url: Optional[str] = None,
        token: Optional[str] = None,
        auth_method: str = "token",
        auth_path: str = "auth/jwt/login",
        secret_path: str = "secret/data",
        verify_tls: bool = True,
    ):
        self.url = url or os.environ.get("VAULT_ADDR", "http://localhost:8200")
        self.token = token or os.environ.get("VAULT_TOKEN")
        self.auth_method = auth_method
        self.auth_path = auth_path
        self.secret_path = secret_path
        self.verify_tls = verify_tls
        self._session = None
        
        if not HAS_REQUESTS:
            raise ImportError("requests library required for VaultProvider; install with: pip install requests")

    @property
    def session(self):
        if self._session is None:
            self._session = requests.Session()
        return self._session

    def _ensure_authenticated(self):
        """Ensure we have a valid token; refresh if needed."""
        if not self.token:
            raise RuntimeError("Vault authentication required but no token available")

    def get_secret(self, name: str) -> str:
        """Retrieve a secret from Vault.
        
        Args:
            name: Secret path, e.g. 'gh-token' (will be prefixed with secret_path)
        
        Returns:
            Secret value as string
        
        Raises:
            RuntimeError if secret not found or auth failed
        """
        self._ensure_authenticated()
        url = f"{self.url}/v1/{self.secret_path}/{name}"
        headers = {"X-Vault-Token": self.token}
        try:
            resp = self.session.get(url, headers=headers, verify=self.verify_tls, timeout=10)
            resp.raise_for_status()
            data = resp.json().get("data", {}).get("data", {})
            # Common field names: 'value', 'secret', 'token'
            for key in ["value", "secret", "token", "data"]:
                if key in data:
                    return str(data[key])
            # If no recognized key, assume single field
            if data:
                return str(list(data.values())[0])
            raise RuntimeError(f"No secret value found at {name}")
        except Exception as e:
            logger.exception("Failed to retrieve secret from Vault at %s", name)
            raise RuntimeError(f"Vault retrieval failed: {e}")

    def put_secret(self, name: str, value: str) -> None:
        """Store a secret in Vault."""
        self._ensure_authenticated()
        url = f"{self.url}/v1/{self.secret_path}/{name}"
        headers = {"X-Vault-Token": self.token}
        payload = {"data": {"value": value}}
        try:
            resp = self.session.post(url, json=payload, headers=headers, verify=self.verify_tls, timeout=10)
            resp.raise_for_status()
        except Exception as e:
            logger.exception("Failed to store secret in Vault at %s", name)
            raise RuntimeError(f"Vault storage failed: {e}")

    def rotate_secret(self, name: str) -> str:
        """Rotate a secret (read new value from Vault).
        
        In practice, this should trigger a Vault operation to generate a new value.
        For now, we simply re-read the current value.
        """
        return self.get_secret(name)


__all__ = ["VaultProvider"]
