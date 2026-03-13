"""
Backend Validation System for Deployment Tokens
Provides comprehensive token validation, expiry checking, and scope verification.
"""

import hmac
import hashlib
import json
import os
import logging
from typing import Optional, Dict, List, Tuple, Any
from datetime import datetime, timedelta
from enum import Enum
import re

logger = logging.getLogger(__name__)


class TokenType(str, Enum):
    """Deployment token types."""
    DEPLOYMENT = "deployment"
    ROLLBACK = "rollback"
    HOTFIX = "hotfix"
    EMERGENCY = "emergency"
    SERVICE = "service"


class TokenScope(str, Enum):
    """Token permission scopes."""
    READ_ONLY = "read:only"
    DEPLOY_STAGING = "deploy:staging"
    DEPLOY_PRODUCTION = "deploy:production"
    ROLLBACK_FULL = "rollback:full"
    ADMIN = "admin"


class TokenStatus(str, Enum):
    """Token lifecycle status."""
    ACTIVE = "active"
    REVOKED = "revoked"
    EXPIRED = "expired"
    SUSPENDED = "suspended"


class ValidationError(Exception):
    """Token validation error."""
    pass


class TokenMetadata:
    """Token metadata and claims."""
    
    def __init__(
        self,
        token_id: str,
        token_type: TokenType,
        scopes: List[TokenScope],
        issued_at: datetime,
        expires_at: datetime,
        issued_by: str,
        subject: str,
        metadata: Optional[Dict[str, Any]] = None
    ):
        self.token_id = token_id
        self.token_type = token_type
        self.scopes = scopes
        self.issued_at = issued_at
        self.expires_at = expires_at
        self.issued_by = issued_by
        self.subject = subject
        self.metadata = metadata or {}
        self.status = TokenStatus.ACTIVE
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "token_id": self.token_id,
            "token_type": self.token_type.value,
            "scopes": [s.value for s in self.scopes],
            "issued_at": self.issued_at.isoformat(),
            "expires_at": self.expires_at.isoformat(),
            "issued_by": self.issued_by,
            "subject": self.subject,
            "status": self.status.value,
            "metadata": self.metadata
        }


class DeploymentTokenValidator:
    """Validates deployment tokens for authorization and authenticity."""
    
    def __init__(self, secret_key: Optional[str] = None, token_ttl_hours: int = 24):
        self.secret_key = secret_key or os.getenv("DEPLOYMENT_TOKEN_SECRET", "")
        self.token_ttl = timedelta(hours=token_ttl_hours)
        self.revoked_tokens: set = set()
        self.token_store: Dict[str, TokenMetadata] = {}
    
    def generate_token(
        self,
        token_type: TokenType,
        scopes: List[TokenScope],
        subject: str,
        issued_by: str,
        metadata: Optional[Dict[str, Any]] = None
    ) -> Tuple[str, TokenMetadata]:
        """Generate a new deployment token."""
        issued_at = datetime.utcnow()
        expires_at = issued_at + self.token_ttl
        
        token_id = self._generate_token_id()
        token_metadata = TokenMetadata(
            token_id=token_id,
            token_type=token_type,
            scopes=scopes,
            issued_at=issued_at,
            expires_at=expires_at,
            issued_by=issued_by,
            subject=subject,
            metadata=metadata
        )
        
        # Store metadata
        self.token_store[token_id] = token_metadata
        
        # Create JWT-like token
        payload = json.dumps(token_metadata.to_dict())
        signature = self._create_signature(payload)
        token = f"{token_id}.{signature}"
        
        logger.info(f"Generated token {token_id} for {subject}")
        return token, token_metadata
    
    def validate_token(
        self,
        token: str,
        required_scope: Optional[TokenScope] = None,
        required_type: Optional[TokenType] = None
    ) -> Tuple[bool, str, Optional[TokenMetadata]]:
        """
        Validate a deployment token.
        
        Returns:
            Tuple of (is_valid, message, metadata)
        """
        try:
            # Parse token
            if "." not in token:
                return False, "Invalid token format", None
            
            token_id, signature = token.rsplit(".", 1)
            
            # Check if token is revoked
            if token_id in self.revoked_tokens:
                return False, "Token has been revoked", None
            
            # Verify signature
            if token_id not in self.token_store:
                return False, "Token not found", None
            
            metadata = self.token_store[token_id]
            
            # Verify signature
            payload = json.dumps(metadata.to_dict())
            expected_signature = self._create_signature(payload)
            
            if not hmac.compare_digest(signature, expected_signature):
                return False, "Invalid signature", None
            
            # Check expiry
            if metadata.expires_at < datetime.utcnow():
                metadata.status = TokenStatus.EXPIRED
                return False, "Token has expired", metadata
            
            # Check status
            if metadata.status != TokenStatus.ACTIVE:
                return False, f"Token is {metadata.status.value}", metadata
            
            # Verify scope
            if required_scope and required_scope not in metadata.scopes:
                return False, f"Token does not have required scope: {required_scope.value}", metadata
            
            # Verify type
            if required_type and metadata.token_type != required_type:
                return False, f"Token type mismatch. Expected {required_type.value}", metadata
            
            return True, "Token is valid", metadata
            
        except Exception as e:
            logger.error(f"Token validation error: {str(e)}")
            return False, f"Validation error: {str(e)}", None
    
    def revoke_token(self, token_id: str) -> bool:
        """Revoke a token."""
        if token_id in self.token_store:
            self.revoked_tokens.add(token_id)
            self.token_store[token_id].status = TokenStatus.REVOKED
            logger.warning(f"Token {token_id} revoked")
            return True
        return False
    
    def check_scope_hierarchy(self, token_scope: TokenScope, required_scope: TokenScope) -> bool:
        """
        Check if token scope satisfies required scope.
        Admin > Production > Staging > ReadOnly
        """
        scope_hierarchy = {
            TokenScope.ADMIN: 4,
            TokenScope.DEPLOY_PRODUCTION: 3,
            TokenScope.DEPLOY_STAGING: 2,
            TokenScope.READ_ONLY: 1,
            TokenScope.ROLLBACK_FULL: 3
        }
        
        token_level = scope_hierarchy.get(token_scope, 0)
        required_level = scope_hierarchy.get(required_scope, 0)
        
        return token_level >= required_level
    
    def get_token_info(self, token_id: str) -> Optional[Dict[str, Any]]:
        """Get token information."""
        if token_id in self.token_store:
            metadata = self.token_store[token_id]
            info = metadata.to_dict()
            info["time_remaining_seconds"] = (
                metadata.expires_at - datetime.utcnow()
            ).total_seconds()
            return info
        return None
    
    def list_active_tokens(self, subject: Optional[str] = None) -> List[Dict[str, Any]]:
        """List active tokens, optionally filtered by subject."""
        tokens = []
        for token_id, metadata in self.token_store.items():
            if metadata.status != TokenStatus.ACTIVE:
                continue
            if subject and metadata.subject != subject:
                continue
            if metadata.expires_at >= datetime.utcnow():
                tokens.append(metadata.to_dict())
        return tokens
    
    def cleanup_expired_tokens(self) -> int:
        """Remove expired tokens from store."""
        expired = []
        for token_id, metadata in self.token_store.items():
            if metadata.expires_at < datetime.utcnow():
                expired.append(token_id)
        
        for token_id in expired:
            del self.token_store[token_id]
        
        logger.info(f"Cleaned up {len(expired)} expired tokens")
        return len(expired)
    
    def validate_deployment_readiness(
        self,
        token: str,
        target_environment: str
    ) -> Tuple[bool, List[str], Optional[TokenMetadata]]:
        """
        Comprehensive validation for deployment authorization.
        
        Returns:
            Tuple of (is_authorized, validation_messages, metadata)
        """
        messages = []
        
        # Determine required scope
        if target_environment == "production":
            required_scope = TokenScope.DEPLOY_PRODUCTION
        elif target_environment == "staging":
            required_scope = TokenScope.DEPLOY_STAGING
        else:
            required_scope = TokenScope.READ_ONLY
        
        # Validate token
        is_valid, msg, metadata = self.validate_token(token, required_scope=required_scope)
        messages.append(msg)
        
        if not is_valid:
            return False, messages, metadata
        
        # Additional checks
        if metadata.metadata.get("restricted_deployments"):
            deployments = metadata.metadata["restricted_deployments"]
            if target_environment not in deployments:
                messages.append(f"Deployment restricted to: {deployments}")
                return False, messages, metadata
        
        messages.append("Authorization granted for deployment")
        return True, messages, metadata
    
    def _generate_token_id(self) -> str:
        """Generate unique token ID."""
        import uuid
        return f"dtoken_{uuid.uuid4().hex[:16]}"
    
    def _create_signature(self, payload: str) -> str:
        """Create HMAC signature for payload."""
        if not self.secret_key:
            raise ValueError("Secret key not configured")
        
        return hmac.new(
            self.secret_key.encode(),
            payload.encode(),
            hashlib.sha256
        ).hexdigest()


class TokenAuditLogger:
    """Audit logging for token operations."""
    
    def __init__(self, log_file: str = "token_audit.log"):
        self.log_file = log_file
    
    def log_validation(
        self,
        token_id: str,
        is_valid: bool,
        subject: str,
        scope: str,
        timestamp: Optional[datetime] = None
    ):
        """Log token validation attempt."""
        timestamp = timestamp or datetime.utcnow()
        entry = {
            "timestamp": timestamp.isoformat(),
            "event": "token_validation",
            "token_id": token_id,
            "is_valid": is_valid,
            "subject": subject,
            "scope": scope
        }
        
        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
    
    def log_generation(
        self,
        token_id: str,
        token_type: str,
        subject: str,
        issued_by: str,
        timestamp: Optional[datetime] = None
    ):
        """Log token generation."""
        timestamp = timestamp or datetime.utcnow()
        entry = {
            "timestamp": timestamp.isoformat(),
            "event": "token_generation",
            "token_id": token_id,
            "token_type": token_type,
            "subject": subject,
            "issued_by": issued_by
        }
        
        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
    
    def log_revocation(
        self,
        token_id: str,
        revoked_by: str,
        reason: str,
        timestamp: Optional[datetime] = None
    ):
        """Log token revocation."""
        timestamp = timestamp or datetime.utcnow()
        entry = {
            "timestamp": timestamp.isoformat(),
            "event": "token_revocation",
            "token_id": token_id,
            "revoked_by": revoked_by,
            "reason": reason
        }
        
        with open(self.log_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
