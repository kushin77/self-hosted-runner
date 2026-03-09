"""Credential Manager with real SDK-backed providers for GSM/VAULT/AWS.

This module provides a cache-aware secret manager that supports multiple backends:
- Google Secret Manager (via google-cloud-secret-manager)
- HashiCorp Vault (via HTTP client)
- AWS Secrets Manager (via boto3)

Secrets are cached with TTL and never logged directly.
"""
from __future__ import annotations

import time
from typing import Dict, Optional
import threading

from .providers.vault_provider import VaultProvider
from .providers.gsm_provider import GoogleSecretManagerProvider
from .providers.aws_provider import AWSSecretsManagerProvider


class SecretProvider:
    """Abstract secret provider interface."""

    def get_secret(self, name: str) -> str:
        raise NotImplementedError()

    def put_secret(self, name: str, value: str) -> None:
        raise NotImplementedError()

    def rotate_secret(self, name: str) -> str:
        raise NotImplementedError()


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
            return GoogleSecretManagerProvider(config.get("project_id"))
        if provider in ("vault", "hashicorp"):
            return VaultProvider(
                url=config.get("url"),
                token=config.get("token"),
                auth_method=config.get("auth_method", "token"),
                auth_path=config.get("auth_path", "auth/jwt/login"),
                secret_path=config.get("secret_path", "secret/data"),
                verify_tls=config.get("verify_tls", True),
            )
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
]
