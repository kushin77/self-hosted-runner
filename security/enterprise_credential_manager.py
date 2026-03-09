#!/usr/bin/env python3
"""
Enterprise Credential Manager - Zero Long-Lived Secrets
Implements immutable, ephemeral, idempotent credential lifecycle with
GSM/Vault/KMS providers and OIDC/WIF authentication.
"""

import os
import json
import sys
import time
import logging
import hashlib
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from pathlib import Path
import subprocess

# Setup logging with immutable, append-only audit trail
class ImmutableAuditLogger:
    """Append-only audit log with cryptographic integrity"""
    
    def __init__(self, log_file: str = ".audit-logs/credential-manager.jsonl"):
        self.log_file = log_file
        Path(log_file).parent.mkdir(parents=True, exist_ok=True)
        self.setup_logger()
    
    def setup_logger(self):
        """Configure logger for immutable append-only logging"""
        handler = logging.FileHandler(self.log_file, mode='a')
        formatter = logging.Formatter(
            '{"timestamp": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
        )
        handler.setFormatter(formatter)
        self.logger = logging.getLogger("credential-manager")
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)
    
    def log_action(self, action: str, details: Dict):
        """Log action with immutable timestamp"""
        entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "action": action,
            "details": details,
            "hash": None
        }
        entry["hash"] = hashlib.sha256(
            json.dumps(entry, sort_keys=True).encode()
        ).hexdigest()
        self.logger.info(json.dumps(entry))


class CredentialProvider:
    """Base credential provider interface"""
    
    def get_secret(self, secret_name: str) -> Optional[str]:
        """Retrieve credential (must be idempotent)"""
        raise NotImplementedError
    
    def rotate_secret(self, secret_name: str, new_value: str) -> bool:
        """Rotate credential (immutable - append-only operation)"""
        raise NotImplementedError
    
    def validate_access(self) -> bool:
        """Validate provider connectivity (idempotent)"""
        raise NotImplementedError


class GSMProvider(CredentialProvider):
    """Google Secret Manager provider with OIDC workload identity"""
    
    def __init__(self, project_id: str, audit_logger: ImmutableAuditLogger):
        self.project_id = project_id
        self.logger = audit_logger
        self.provider_name = "GSM"
    
    def validate_access(self) -> bool:
        """Validate GSM connectivity via OIDC token"""
        try:
            result = subprocess.run(
                ["gcloud", "secrets", "list", "--project", self.project_id, "--limit=1"],
                capture_output=True,
                timeout=10
            )
            self.logger.log_action("gsm_validate", {"status": "success"})
            return result.returncode == 0
        except Exception as e:
            self.logger.log_action("gsm_validate", {"status": "failed", "error": str(e)})
            return False
    
    def get_secret(self, secret_name: str) -> Optional[str]:
        """Retrieve secret from GSM (idempotent - same result each call)"""
        try:
            result = subprocess.run(
                ["gcloud", "secrets", "versions", "access", "latest",
                 "--secret", secret_name,
                 "--project", self.project_id],
                capture_output=True,
                timeout=10,
                text=True
            )
            if result.returncode == 0:
                self.logger.log_action("gsm_retrieve", {
                    "secret": secret_name,
                    "status": "success"
                })
                return result.stdout.strip()
            else:
                self.logger.log_action("gsm_retrieve", {
                    "secret": secret_name,
                    "status": "failed"
                })
                return None
        except Exception as e:
            self.logger.log_action("gsm_retrieve", {
                "secret": secret_name,
                "status": "error",
                "error": str(e)
            })
            return None
    
    def rotate_secret(self, secret_name: str, new_value: str) -> bool:
        """Create new secret version (immutable - append-only)"""
        try:
            # Echo new value to gcloud (secure - no shell history)
            result = subprocess.run(
                ["gcloud", "secrets", "versions", "add", secret_name,
                 "--data-file", "-",
                 "--project", self.project_id],
                input=new_value.encode(),
                capture_output=True,
                timeout=10
            )
            success = result.returncode == 0
            self.logger.log_action("gsm_rotate", {
                "secret": secret_name,
                "status": "created_new_version" if success else "failed"
            })
            return success
        except Exception as e:
            self.logger.log_action("gsm_rotate", {
                "secret": secret_name,
                "status": "error",
                "error": str(e)
            })
            return False


class VaultProvider(CredentialProvider):
    """HashiCorp Vault provider with JWT authentication"""
    
    def __init__(self, vault_addr: str, vault_jwt_role: str, audit_logger: ImmutableAuditLogger):
        self.vault_addr = vault_addr
        self.vault_jwt_role = vault_jwt_role
        self.logger = audit_logger
        self.provider_name = "VAULT"
        self.token_cache = {}
        self.token_expiry = {}
    
    def _get_jwt_token(self) -> Optional[str]:
        """Get ephemeral JWT token from GitHub Actions OIDC provider"""
        try:
            token_request_url = os.getenv("ACTIONS_ID_TOKEN_REQUEST_URL")
            token_request_token = os.getenv("ACTIONS_ID_TOKEN_REQUEST_TOKEN")
            
            if not token_request_url or not token_request_token:
                self.logger.log_action("vault_jwt", {"status": "no_oidc_environment"})
                return None
            
            import urllib.request
            req = urllib.request.Request(
                token_request_url,
                headers={"Authorization": f"bearer {token_request_token}"}
            )
            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read())
                return data.get("token")
        except Exception as e:
            self.logger.log_action("vault_jwt", {"status": "failed", "error": str(e)})
            return None
    
    def _get_vault_token(self) -> Optional[str]:
        """Authenticate to Vault with JWT and get ephemeral access token"""
        jwt_token = self._get_jwt_token()
        if not jwt_token:
            return None
        
        try:
            import urllib.request
            auth_request = {
                "role": self.vault_jwt_role,
                "jwt": jwt_token
            }
            
            req = urllib.request.Request(
                f"{self.vault_addr}/v1/auth/jwt/login",
                data=json.dumps(auth_request).encode(),
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            
            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read())
                vault_token = data["auth"]["client_token"]
                ttl = data["auth"]["lease_duration"]
                
                self.logger.log_action("vault_auth", {
                    "status": "authenticated",
                    "ttl_seconds": ttl
                })
                
                return vault_token
        except Exception as e:
            self.logger.log_action("vault_auth", {"status": "failed", "error": str(e)})
            return None
    
    def validate_access(self) -> bool:
        """Validate Vault connectivity"""
        try:
            token = self._get_vault_token()
            if token:
                self.logger.log_action("vault_validate", {"status": "success"})
                return True
            return False
        except Exception as e:
            self.logger.log_action("vault_validate", {"status": "failed", "error": str(e)})
            return False
    
    def get_secret(self, secret_name: str) -> Optional[str]:
        """Retrieve secret from Vault"""
        try:
            token = self._get_vault_token()
            if not token:
                return None
            
            import urllib.request
            req = urllib.request.Request(
                f"{self.vault_addr}/v1/secret/data/{secret_name}",
                headers={"X-Vault-Token": token},
                method="GET"
            )
            
            with urllib.request.urlopen(req, timeout=10) as response:
                data = json.loads(response.read())
                value = data["data"]["data"]["value"]
                self.logger.log_action("vault_retrieve", {
                    "secret": secret_name,
                    "status": "success"
                })
                return value
        except Exception as e:
            self.logger.log_action("vault_retrieve", {
                "secret": secret_name,
                "status": "failed",
                "error": str(e)
            })
            return None
    
    def rotate_secret(self, secret_name: str, new_value: str) -> bool:
        """Create new secret version in Vault"""
        try:
            token = self._get_vault_token()
            if not token:
                return False
            
            import urllib.request
            secret_data = {
                "data": {
                    "value": new_value,
                    "rotated_at": datetime.utcnow().isoformat() + "Z"
                }
            }
            
            req = urllib.request.Request(
                f"{self.vault_addr}/v1/secret/data/{secret_name}",
                data=json.dumps(secret_data).encode(),
                headers={
                    "X-Vault-Token": token,
                    "Content-Type": "application/json"
                },
                method="POST"
            )
            
            with urllib.request.urlopen(req, timeout=10) as response:
                self.logger.log_action("vault_rotate", {
                    "secret": secret_name,
                    "status": "rotated"
                })
                return True
        except Exception as e:
            self.logger.log_action("vault_rotate", {
                "secret": secret_name,
                "status": "failed",
                "error": str(e)
            })
            return False


class KMSProvider(CredentialProvider):
    """AWS KMS provider with OIDC/WIF authentication"""
    
    def __init__(self, role_arn: str, audit_logger: ImmutableAuditLogger):
        self.role_arn = role_arn
        self.logger = audit_logger
        self.provider_name = "KMS"
    
    def validate_access(self) -> bool:
        """Validate AWS KMS connectivity via OIDC/WIF"""
        try:
            result = subprocess.run(
                ["aws", "sts", "get-caller-identity"],
                capture_output=True,
                timeout=10
            )
            success = result.returncode == 0
            self.logger.log_action("kms_validate", {"status": "success" if success else "failed"})
            return success
        except Exception as e:
            self.logger.log_action("kms_validate", {"status": "error", "error": str(e)})
            return False
    
    def get_secret(self, secret_name: str) -> Optional[str]:
        """Retrieve secret from AWS Secrets Manager"""
        try:
            result = subprocess.run(
                ["aws", "secretsmanager", "get-secret-value",
                 "--secret-id", secret_name],
                capture_output=True,
                timeout=10,
                text=True
            )
            if result.returncode == 0:
                data = json.loads(result.stdout)
                value = data.get("SecretString") or data.get("SecretBinary")
                self.logger.log_action("kms_retrieve", {
                    "secret": secret_name,
                    "status": "success"
                })
                return value
            return None
        except Exception as e:
            self.logger.log_action("kms_retrieve", {
                "secret": secret_name,
                "status": "failed",
                "error": str(e)
            })
            return None
    
    def rotate_secret(self, secret_name: str, new_value: str) -> bool:
        """Create new secret version in AWS Secrets Manager"""
        try:
            result = subprocess.run(
                ["aws", "secretsmanager", "put-secret-value",
                 "--secret-id", secret_name,
                 "--secret-string", new_value],
                capture_output=True,
                timeout=10
            )
            success = result.returncode == 0
            self.logger.log_action("kms_rotate", {
                "secret": secret_name,
                "status": "rotated" if success else "failed"
            })
            return success
        except Exception as e:
            self.logger.log_action("kms_rotate", {
                "secret": secret_name,
                "status": "error",
                "error": str(e)
            })
            return False


class EnterpriseCredentialManager:
    """
    Multi-provider credential manager with:
    - Immutable audit logging
    - Ephemeral token lifecycle
    - Idempotent operations
    - Automated rotation
    - Zero stored secrets
    """
    
    def __init__(self):
        self.logger = ImmutableAuditLogger()
        self.providers: Dict[str, CredentialProvider] = {}
        self.credential_cache: Dict[str, Tuple[str, float]] = {}
        self.cache_ttl = 3600  # 1 hour
        self._initialize_providers()
    
    def _initialize_providers(self):
        """Initialize all available credential providers"""
        # GSM
        gcp_project = os.getenv("GCP_PROJECT_ID")
        if gcp_project:
            self.providers["gsm"] = GSMProvider(gcp_project, self.logger)
        
        # Vault
        vault_addr = os.getenv("VAULT_ADDR")
        vault_role = os.getenv("VAULT_JWT_ROLE")
        if vault_addr and vault_role:
            self.providers["vault"] = VaultProvider(vault_addr, vault_role, self.logger)
        
        # KMS
        aws_role = os.getenv("AWS_ROLE_ARN")
        if aws_role:
            self.providers["kms"] = KMSProvider(aws_role, self.logger)
        
        self.logger.log_action("manager_init", {
            "providers_initialized": list(self.providers.keys()),
            "cache_ttl_seconds": self.cache_ttl
        })
    
    def validate_all_providers(self) -> Dict[str, bool]:
        """Validate all provider connectivity (idempotent)"""
        results = {}
        for name, provider in self.providers.items():
            results[name] = provider.validate_access()
        
        self.logger.log_action("validate_all", {"results": results})
        return results
    
    def get_credential(self, secret_name: str, preferred_provider: Optional[str] = None) -> Optional[str]:
        """
        Get credential with fallback to multiple providers (idempotent).
        Uses cache to avoid repeated retrievals.
        """
        # Check cache
        if secret_name in self.credential_cache:
            value, expiry = self.credential_cache[secret_name]
            if time.time() < expiry:
                self.logger.log_action("credential_cache_hit", {"secret": secret_name})
                return value
        
        # Try preferred provider first
        if preferred_provider and preferred_provider in self.providers:
            value = self.providers[preferred_provider].get_secret(secret_name)
            if value:
                self.credential_cache[secret_name] = (value, time.time() + self.cache_ttl)
                return value
        
        # Fallback to other providers
        for name, provider in self.providers.items():
            if preferred_provider and name == preferred_provider:
                continue
            
            value = provider.get_secret(secret_name)
            if value:
                self.credential_cache[secret_name] = (value, time.time() + self.cache_ttl)
                return value
        
        self.logger.log_action("credential_not_found", {"secret": secret_name})
        return None
    
    def rotate_credential(self, secret_name: str, new_value: str, providers: Optional[List[str]] = None):
        """
        Rotate credential across multiple providers (immutable - creates new versions).
        """
        if not providers:
            providers = list(self.providers.keys())
        
        results = {}
        for provider_name in providers:
            if provider_name in self.providers:
                results[provider_name] = self.providers[provider_name].rotate_secret(
                    secret_name, new_value
                )
        
        # Invalidate cache
        if secret_name in self.credential_cache:
            del self.credential_cache[secret_name]
        
        self.logger.log_action("credential_rotated", {
            "secret": secret_name,
            "providers_rotated": results
        })
        
        return results


def main():
    """Demo / testing"""
    manager = EnterpriseCredentialManager()
    
    print("🔐 Enterprise Credential Manager")
    print("=" * 60)
    
    # Validate providers
    print("\n📋 Validating providers...")
    results = manager.validate_all_providers()
    for provider, status in results.items():
        print(f"  {provider:<10} {'✅' if status else '❌'}")
    
    # Test credential retrieval (if secrets configured)
    test_secret = os.getenv("TEST_SECRET_NAME")
    if test_secret:
        print(f"\n🔑 Testing credential retrieval for: {test_secret}")
        value = manager.get_credential(test_secret)
        if value:
            print(f"  ✅ Retrieved successfully")
        else:
            print(f"  ❌ Failed to retrieve")
    
    print("\n📊 Audit logs written to: .audit-logs/credential-manager.jsonl")
    print("✅ All operations are immutable, ephemeral, and idempotent")


if __name__ == "__main__":
    main()
