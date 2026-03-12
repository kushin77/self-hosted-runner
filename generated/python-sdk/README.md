# NexusShield Python SDK

Enterprise credential management, observability, and orchestration API client for Python.

## Installation

```bash
pip install nexusshield-sdk
```

Or from source:

```bash
git clone https://github.com/nexusshield/sdk-python.git
cd sdk-python
pip install -e .
```

## Quick Start

```python
from nexusshield import create_client, Provider

# Create client
client = create_client(api_key='your-api-key')

# Get health status
health = client.get_health()
print(f"Status: {health.data.status}")

# List credentials
creds = client.list_credentials(type='aws_role')
print(f"Found {len(creds.data['credentials'])} credentials")

# Rotate credential
result = client.rotate_credential('cred_123', force=True)
print(f"Rotated at {result.data['rotated_at']}")
```

## API Methods

### Authentication

- `login(provider, code)` - OAuth 2.0 login
- `logout()` - Logout current session
- `get_current_user()` - Get current user info

### Credential Management

- `list_credentials(**filters)` - List credentials
- `get_credential(id)` - Get specific credential
- `create_credential(name, type, provider, config)` - Create credential
- `delete_credential(id)` - Delete credential
- `rotate_credential(id, force=False)` - Rotate credential

### System

- `get_health()` - Get system health

### Audit

- `get_audit_log(...)` - Get audit trail

## Error Handling

All responses follow the unified APIResponse format:

```python
response = client.list_credentials()

if response.is_success():
    print(f"Found {len(response.data['credentials'])} credentials")
elif response.is_partial():
    print(f"Partial success. Warnings: {response.metadata.warnings}")
else:
    print(f"Error: {response.error.code}")
    print(f"Retryable: {response.error.retryable}")
```

## Type Hints

Full type support for IDE autocomplete:

```python
from nexusshield import NexusShieldClient, APIResponse, Credential

client: NexusShieldClient = create_client()
response: APIResponse[dict] = client.list_credentials()
```

## Configuration

```python
client = create_client(
    base_url='https://api.nexusshield.cloud',
    api_key='your-key',
    timeout=30,
    max_retries=3,
    retry_delay=1.0,
)
```

Environment variable fallback:
- API Key: `NEXUS_API_KEY`

## Examples

### Login with GitHub

```python
from nexusshield import Provider

response = client.login(Provider.GITHUB, code='github_oauth_code')
if response.is_success():
    print(f"Logged in as {response.data['user']['email']}")
    access_token = response.data['access_token']
```

### Create AWS Role credential

```python
response = client.create_credential(
    name='Production AWS',
    type_='aws_role',
    provider='github',
    config={
        'role_arn': 'arn:aws:iam::123456789:role/github-actions',
        'duration_seconds': 3600,
    }
)
print(f"Created: {response.data['id']}")
```

### Get audit trail

```python
response = client.get_audit_log(
    limit=50,
    resource_id='cred_123',
    action='ROTATE',
)

for event in response.data['events']:
    print(f"{event['timestamp']}: {event['action']}")
```

## Retry Behavior

The SDK automatically retries transient failures:
- Rate limits (429)
- Server errors (502, 503, 504)

Uses exponential backoff with configurable initial delay.

## License

Apache 2.0
