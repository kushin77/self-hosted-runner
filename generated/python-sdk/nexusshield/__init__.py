"""
NexusShield SDK - Python Client
Enterprise credential management, observability, and orchestration API
Version: 1.0.0
"""

from typing import Optional, Dict, Any, List, Literal, TypeVar, Generic, Union
from dataclasses import dataclass, field, asdict
from datetime import datetime
import os
import time
import json
from enum import Enum

try:
    import requests
    from requests.adapters import HTTPAdapter
    from urllib3.util.retry import Retry as UrlRetry
except ImportError:
    raise ImportError("requests library is required. Install with: pip install requests")

T = TypeVar('T')

class Status(str, Enum):
    """Response status enum"""
    SUCCESS = "success"
    ERROR = "error"
    PARTIAL = "partial"


class CredentialStatus(str, Enum):
    """Credential status enum"""
    ACTIVE = "active"
    ROTATING = "rotating"
    EXPIRED = "expired"
    REVOKED = "revoked"


class Provider(str, Enum):
    """OAuth provider enum"""
    GITHUB = "github"
    GOOGLE = "google"


@dataclass
class ErrorPayload:
    """Error response payload"""
    code: str
    message: str
    retryable: bool
    retryAfter: Optional[int] = None
    details: Optional[Dict[str, Any]] = None


@dataclass
class ResponseMetadata:
    """Response metadata"""
    requestId: str
    timestamp: str
    version: str
    warnings: List[str] = field(default_factory=list)

    @staticmethod
    def from_dict(data: Dict[str, Any]) -> 'ResponseMetadata':
        return ResponseMetadata(
            requestId=data.get('requestId', ''),
            timestamp=data.get('timestamp', ''),
            version=data.get('version', ''),
            warnings=data.get('warnings', []),
        )


@dataclass
class APIResponse(Generic[T]):
    """Unified API response wrapper"""
    status: Status
    data: Optional[T] = None
    error: Optional[ErrorPayload] = None
    metadata: Optional[ResponseMetadata] = None

    def is_success(self) -> bool:
        return self.status == Status.SUCCESS

    def is_error(self) -> bool:
        return self.status == Status.ERROR

    def is_partial(self) -> bool:
        return self.status == Status.PARTIAL


@dataclass
class User:
    """User model"""
    id: str
    email: str
    name: str
    avatar_url: Optional[str] = None
    created_at: Optional[str] = None


@dataclass
class Credential:
    """Credential model"""
    id: str
    name: str
    type: str
    provider: str
    status: CredentialStatus
    expires_at: Optional[str] = None
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


@dataclass
class HealthStatus:
    """Health check response"""
    status: Literal['ok', 'degraded', 'unhealthy']
    timestamp: Optional[str] = None
    uptime_seconds: Optional[int] = None
    components: Optional[Dict[str, str]] = None


class NexusShieldClient:
    """
    NexusShield API Client for Python
    
    Example:
        >>> client = NexusShieldClient(api_key='your-api-key')
        >>> response = await client.get_health()
        >>> if response.is_success():
        ...     print(f"Status: {response.data.status}")
    """

    def __init__(
        self,
        base_url: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout: int = 30,
        max_retries: int = 3,
        retry_delay: float = 1.0,
    ):
        """
        Initialize NexusShield client
        
        Args:
            base_url: API base URL (default: https://api.nexusshield.cloud)
            api_key: Bearer token (falls back to NEXUS_API_KEY env var)
            timeout: Request timeout in seconds
            max_retries: Maximum retry attempts
            retry_delay: Initial retry delay in seconds (exponential backoff)
        """
        self.base_url = base_url or "https://api.nexusshield.cloud"
        self.api_key = api_key or os.getenv("NEXUS_API_KEY", "")
        self.timeout = timeout
        self.max_retries = max_retries
        self.retry_delay = retry_delay

        # Setup session with retry strategy
        self.session = requests.Session()
        retry_strategy = UrlRetry(
            total=max_retries,
            backoff_factor=1,
            status_forcelist=[429, 502, 503, 504],
            allowed_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

        # Set default headers
        self.session.headers.update({
            'Content-Type': 'application/json',
            'User-Agent': 'NexusShield-SDK/1.0.0-python',
        })

        if self.api_key:
            self.session.headers.update({
                'Authorization': f'Bearer {self.api_key}',
            })

    def _parse_response(self, response: requests.Response) -> Dict[str, Any]:
        """Parse and validate JSON response"""
        try:
            return response.json()
        except json.JSONDecodeError:
            raise ValueError(f"Invalid JSON response: {response.text}")

    def _build_url(self, path: str) -> str:
        """Build full URL"""
        return f"{self.base_url}{path}"

    def _handle_response(self, response: requests.Response) -> APIResponse:
        """Handle HTTP response and return APIResponse"""
        try:
            data = self._parse_response(response)
            
            # Parse metadata
            metadata = None
            if 'metadata' in data:
                metadata = ResponseMetadata.from_dict(data['metadata'])

            # Parse error if present
            error = None
            if 'error' in data and data['error']:
                error = ErrorPayload(**data['error'])

            return APIResponse(
                status=Status(data.get('status', 'error')),
                data=data.get('data'),
                error=error,
                metadata=metadata,
            )
        except Exception as e:
            raise RuntimeError(f"Failed to parse API response: {str(e)}")

    def get(self, path: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Perform GET request"""
        try:
            response = self.session.get(
                self._build_url(path),
                params=params,
                timeout=self.timeout,
            )
            response.raise_for_status()
            return self._parse_response(response)
        except requests.RequestException as e:
            raise RuntimeError(f"GET {path} failed: {str(e)}")

    def post(self, path: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Perform POST request"""
        try:
            response = self.session.post(
                self._build_url(path),
                json=data,
                timeout=self.timeout,
            )
            response.raise_for_status()
            return self._parse_response(response)
        except requests.RequestException as e:
            raise RuntimeError(f"POST {path} failed: {str(e)}")

    def delete(self, path: str) -> Dict[str, Any]:
        """Perform DELETE request"""
        try:
            response = self.session.delete(
                self._build_url(path),
                timeout=self.timeout,
            )
            response.raise_for_status()
            return self._parse_response(response)
        except requests.RequestException as e:
            raise RuntimeError(f"DELETE {path} failed: {str(e)}")

    # Health endpoint
    def get_health(self) -> APIResponse[HealthStatus]:
        """Get system health status"""
        data = self.get('/api/v1/health')
        return self._handle_response(requests.Response())

    # Authentication endpoints
    def login(self, provider: Provider, code: str) -> APIResponse[Dict[str, Any]]:
        """Login via OAuth provider"""
        response_data = self.post('/api/v1/auth/login', {
            'provider': provider.value,
            'code': code,
        })
        return self._handle_response(requests.Response())

    def logout(self) -> APIResponse[Dict[str, str]]:
        """Logout current session"""
        response_data = self.post('/api/v1/auth/logout')
        return self._handle_response(requests.Response())

    def get_current_user(self) -> APIResponse[User]:
        """Get current authenticated user"""
        response_data = self.get('/api/v1/auth/me')
        return self._handle_response(requests.Response())

    # Credential endpoints
    def list_credentials(
        self, 
        **filters: Any
    ) -> APIResponse[Dict[str, Any]]:
        """List all credentials with optional filters"""
        response_data = self.get('/api/v1/credentials', params=filters)
        return self._handle_response(requests.Response())

    def get_credential(self, credential_id: str) -> APIResponse[Credential]:
        """Get credential details"""
        response_data = self.get(f'/api/v1/credentials/{credential_id}')
        return self._handle_response(requests.Response())

    def create_credential(
        self,
        name: str,
        type_: str,
        provider: str,
        config: Dict[str, Any],
    ) -> APIResponse[Credential]:
        """Create new credential"""
        response_data = self.post('/api/v1/credentials', {
            'name': name,
            'type': type_,
            'provider': provider,
            'config': config,
        })
        return self._handle_response(requests.Response())

    def delete_credential(self, credential_id: str) -> APIResponse[Dict[str, str]]:
        """Delete credential"""
        response_data = self.delete(f'/api/v1/credentials/{credential_id}')
        return self._handle_response(requests.Response())

    def rotate_credential(
        self,
        credential_id: str,
        force: bool = False,
    ) -> APIResponse[Dict[str, Any]]:
        """Rotate credential"""
        response_data = self.post(
            f'/api/v1/credentials/{credential_id}/rotate',
            {'force': force},
        )
        return self._handle_response(requests.Response())

    # Audit endpoint
    def get_audit_log(
        self,
        limit: int = 100,
        offset: int = 0,
        resource_id: Optional[str] = None,
        action: Optional[str] = None,
        date_from: Optional[str] = None,
        date_to: Optional[str] = None,
    ) -> APIResponse[Dict[str, Any]]:
        """Get audit trail"""
        params = {
            'limit': limit,
            'offset': offset,
        }
        if resource_id:
            params['resource_id'] = resource_id
        if action:
            params['action'] = action
        if date_from:
            params['date_from'] = date_from
        if date_to:
            params['date_to'] = date_to

        response_data = self.get('/api/v1/audit', params=params)
        return self._handle_response(requests.Response())


def create_client(
    base_url: Optional[str] = None,
    api_key: Optional[str] = None,
    **kwargs: Any
) -> NexusShieldClient:
    """Factory function to create client"""
    return NexusShieldClient(base_url=base_url, api_key=api_key, **kwargs)


__all__ = [
    'NexusShieldClient',
    'create_client',
    # Types
    'APIResponse',
    'ErrorPayload',
    'ResponseMetadata',
    'User',
    'Credential',
    'HealthStatus',
    'Status',
    'CredentialStatus',
    'Provider',
]
