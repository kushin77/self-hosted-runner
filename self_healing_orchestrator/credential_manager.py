"""Credential Manager abstraction and placeholder providers for GSM/VAULT/KMS.

This module provides a small, testable interface for secret retrieval and
rotation. Backends are implemented as placeholders that can be extended to
call real provider SDKs. The implementation is intentionally minimal and
safe — no secrets are logged and calls raise clear errors when unimplemented.
"""
from __future__ import annotations

import time
from typing import Dict, Optional
import threading


class SecretProvider:
    """Abstract secret provider interface."""

    def get_secret(self, name: str) -> str:
        raise NotImplementedError()

    def put_secret(self, name: str, value: str) -> None:
        raise NotImplementedError()

    def rotate_secret(self, name: str) -> str:
        raise NotImplementedError()


class GoogleSecretManagerProvider(SecretProvider):
    def __init__(self, project: Optional[str] = None):
        self.project = project

    def get_secret(self, name: str) -> str:
        raise NotImplementedError("Google Secret Manager provider not implemented")

    def put_secret(self, name: str, value: str) -> None:
        raise NotImplementedError("Google Secret Manager provider not implemented")

    def rotate_secret(self, name: str) -> str:
        raise NotImplementedError("Google Secret Manager provider not implemented")


class HashiCorpVaultProvider(SecretProvider):
    def __init__(self, url: Optional[str] = None, token: Optional[str] = None):
        self.url = url
        self.token = token

    def get_secret(self, name: str) -> str:
        raise NotImplementedError("HashiCorp Vault provider not implemented")

    def put_secret(self, name: str, value: str) -> None:
        raise NotImplementedError("HashiCorp Vault provider not implemented")

    def rotate_secret(self, name: str) -> str:
        raise NotImplementedError("HashiCorp Vault provider not implemented")


class AWSSecretsManagerProvider(SecretProvider):
    def __init__(self, region: Optional[str] = None):
        self.region = region

    def get_secret(self, name: str) -> str:
        raise NotImplementedError("AWS Secrets Manager provider not implemented")

    def put_secret(self, name: str, value: str) -> None:
        raise NotImplementedError("AWS Secrets Manager provider not implemented")

    def rotate_secret(self, name: str) -> str:
        raise NotImplementedError("AWS Secrets Manager provider not implemented")


class CredentialManager:
    """Selects a backend provider and caches secrets with simple TTL.

    Usage:
        cm = CredentialManager(provider="vault", config={...})
        token = cm.get("path/to/secret")
    """

    def __init__(self, provider: str = "vault", config: Optional[Dict] = None, ttl: int = 300):
        self.provider_name = provider
        self.config = config or {}
        self.ttl = ttl
        self._cache: Dict[str, Dict] = {}
        self._lock = threading.Lock()
        self._provider = self._init_provider(provider, self.config)

    def _init_provider(self, provider: str, config: Dict) -> SecretProvider:
        if provider in ("gcp", "gsm", "gcp_sm"):
            return GoogleSecretManagerProvider(config.get("project"))
        if provider in ("vault", "hashicorp"):
            return HashiCorpVaultProvider(config.get("url"), config.get("token"))
        if provider in ("aws", "secretsmanager"):
            return AWSSecretsManagerProvider(config.get("region"))
        raise ValueError(f"Unknown provider: {provider}")

    def get(self, name: str) -> str:
        now = time.time()
        with self._lock:
            entry = self._cache.get(name)
            if entry and entry["expiry"] > now:
                return entry["value"]
        # not cached or expired
        value = self._provider.get_secret(name)
        with self._lock:
            self._cache[name] = {"value": value, "expiry": now + self.ttl}
        return value

    def put(self, name: str, value: str) -> None:
        self._provider.put_secret(name, value)
        with self._lock:
            self._cache[name] = {"value": value, "expiry": time.time() + self.ttl}

    def rotate(self, name: str) -> str:
        new = self._provider.rotate_secret(name)
        with self._lock:
            self._cache[name] = {"value": new, "expiry": time.time() + self.ttl}
        return new


__all__ = [
    "CredentialManager",
    "SecretProvider",
    "GoogleSecretManagerProvider",
    "HashiCorpVaultProvider",
    "AWSSecretsManagerProvider",
]
