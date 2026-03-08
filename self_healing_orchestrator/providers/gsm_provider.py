"""Google Secret Manager provider implementation.

Uses google-cloud-secret-manager library to access GCP Secret Manager.
Credentials are assumed to be available via GOOGLE_APPLICATION_CREDENTIALS
or ADC (Application Default Credentials).
"""
import os
import logging
from typing import Optional

logger = logging.getLogger(__name__)

try:
    from google.cloud import secretmanager
    HAS_GSM = True
except ImportError:
    HAS_GSM = False


class GoogleSecretManagerProvider:
    """Use Google Cloud Secret Manager for secret storage and retrieval."""

    def __init__(self, project_id: Optional[str] = None):
        self.project_id = project_id or os.environ.get("GCP_PROJECT_ID")
        if not self.project_id:
            raise ValueError("GCP_PROJECT_ID environment variable or project_id required")
        
        if not HAS_GSM:
            raise ImportError("google-cloud-secret-manager library required; install with: pip install google-cloud-secret-manager")
        
        self.client = secretmanager.SecretManagerServiceClient()

    def get_secret(self, name: str) -> str:
        """Retrieve a secret from Google Secret Manager.
        
        Args:
            name: Secret name (e.g. 'gh-token')
        
        Returns:
            Secret value as string
        """
        try:
            parent = f"projects/{self.project_id}"
            name_path = f"{parent}/secrets/{name}/versions/latest"
            response = self.client.access_secret_version(request={"name": name_path})
            return response.payload.data.decode("UTF-8")
        except Exception as e:
            logger.exception("Failed to retrieve secret from GSM: %s", name)
            raise RuntimeError(f"GSM retrieval failed: {e}")

    def put_secret(self, name: str, value: str) -> None:
        """Store a secret in Google Secret Manager."""
        try:
            parent = f"projects/{self.project_id}"
            
            # Check if secret exists
            try:
                self.client.get_secret(request={"name": f"{parent}/secrets/{name}"})
                # Secret exists, add a new version
                response = self.client.add_secret_version(
                    request={
                        "parent": f"{parent}/secrets/{name}",
                        "payload": {"data": value.encode("UTF-8")},
                    }
                )
            except Exception:
                # Secret doesn't exist, create it
                secret = self.client.create_secret(
                    request={
                        "parent": parent,
                        "secret_id": name,
                        "secret": {"replication": {"automatic": {}}},
                    }
                )
                self.client.add_secret_version(
                    request={
                        "parent": secret.name,
                        "payload": {"data": value.encode("UTF-8")},
                    }
                )
        except Exception as e:
            logger.exception("Failed to store secret in GSM: %s", name)
            raise RuntimeError(f"GSM storage failed: {e}")

    def rotate_secret(self, name: str) -> str:
        """Rotate a secret (add new version in GSM)."""
        # For rotation, fetch current value and re-store it
        return self.get_secret(name)


__all__ = ["GoogleSecretManagerProvider"]
