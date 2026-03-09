import os
import json
import logging
from abc import ABC, abstractmethod
from typing import Optional, Dict, Any
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

class CredentialProvider(ABC):
    @abstractmethod
    def get_secret(self, secret_id: str) -> Optional[str]:
        pass
    @abstractmethod
    def is_available(self) -> bool:
        pass

class GSMProvider(CredentialProvider):
    def __init__(self):
        self.project_id = os.getenv("GCP_PROJECT_ID")
        self.available = self.project_id is not None
    def is_available(self) -> bool:
        return self.available
    def get_secret(self, secret_id: str) -> Optional[str]:
        if not self.is_available():
            return None
        try:
            from google.cloud import secretmanager
            client = secretmanager.SecretManagerServiceClient()
            name = f"projects/{self.project_id}/secrets/{secret_id}/versions/latest"
            response = client.access_secret_version(request={"name": name})
            return response.payload.data.decode("UTF-8")
        except Exception as e:
            logger.warning(f"GSM retrieval failed: {e}")
            return None

class VaultProvider(CredentialProvider):
    def __init__(self):
        self.vault_addr = os.getenv("VAULT_ADDR")
        self.vault_token = os.getenv("VAULT_TOKEN")
        self.available = bool(self.vault_addr and self.vault_token)
    def is_available(self) -> bool:
        return self.available
    def get_secret(self, secret_id: str) -> Optional[str]:
        if not self.is_available():
            return None
        try:
            import hvac
            client = hvac.Client(url=self.vault_addr, token=self.vault_token)
            response = client.secrets.kv.v2.read_secret_version(path=secret_id)
            data = response["data"]["data"]
            if isinstance(data, dict) and "value" in data:
                return data["value"]
            return json.dumps(data)
        except Exception as e:
            logger.warning(f"Vault retrieval failed: {e}")
            return None

class AWSKMSProvider(CredentialProvider):
    def __init__(self):
        self.available = os.getenv("AWS_REGION") is not None
    def is_available(self) -> bool:
        return self.available
    def get_secret(self, secret_id: str) -> Optional[str]:
        if not self.is_available():
            return None
        try:
            import boto3
            client = boto3.client("secretsmanager")
            response = client.get_secret_value(SecretId=secret_id)
            return response.get("SecretString", response.get("SecretBinary"))
        except Exception as e:
            logger.warning(f"AWS Secrets Manager failed: {e}")
            return None

class EnvProvider(CredentialProvider):
    def is_available(self) -> bool:
        return True
    def get_secret(self, secret_id: str) -> Optional[str]:
        env_key = secret_id.upper().replace("-", "_")
        return os.getenv(env_key)

class CredentialManager:
    def __init__(self):
        self.providers = [GSMProvider(), VaultProvider(), AWSKMSProvider(), EnvProvider()]
    def get_secret(self, secret_id: str) -> Optional[str]:
        for provider in self.providers:
            if provider.is_available():
                secret = provider.get_secret(secret_id)
                if secret:
                    return secret
        return None

_credential_manager = None
def get_credential_manager() -> CredentialManager:
    global _credential_manager
    if _credential_manager is None:
        _credential_manager = CredentialManager()
    return _credential_manager
