# NexusShield CLI

Command-line interface for NexusShield enterprise credential management.

## Installation

### Option 1: Using npm (Recommended)

```bash
npm install -g @nexusshield/cli
```

### Option 2: From source

```bash
git clone <repo>
cd self-hosted-runner

# Install Python SDK
pip install -e generated/python-sdk

# Make CLI globally available
sudo ln -s "$(pwd)/scripts/cli/nexus" /usr/local/bin/nexus
chmod +x scripts/cli/nexus
```

## Quick Start

### 1. Set up authentication

```bash
export NEXUS_API_KEY="your-api-key"
export NEXUS_API_URL="https://api.nexusshield.cloud"  # Optional, defaults to production
```

Get your API key from the [NexusShield Portal](https://portal.nexusshield.cloud)

### 2. Check health

```bash
nexus health
# Output: ✓ NexusShield API is ok
```

### 3. List credentials

```bash
nexus credential list
# Output:
# ID                   Name                          Type            Status
# ----------------------------
# cred_abc123          Production AWS Role           aws_role        active
# cred_def456          Development GCP Account       gcp_sa           active
```

### 4. Get credential details

```bash
nexus credential get cred_abc123
```

### 5. Create credential

```bash
nexus credential create \
  --name "Production AWS" \
  --type aws_role \
  --provider github \
  --config '{"role_arn": "arn:aws:iam::123456789:role/github"}'
```

### 6. Rotate credential

```bash
nexus credential rotate cred_abc123
# Output:
# ✓ Rotated credential: cred_abc123
#   Rotated at: 2026-03-12T13:05:00Z
#   Expires at: 2026-03-13T13:05:00Z
```

### 7. Delete credential

```bash
nexus credential delete cred_abc123 --force
```

### 8. View audit trail

```bash
nexus audit log --limit 50 --resource-id cred_abc123 --action ROTATE
```

## Commands Reference

### Health Check

```bash
nexus health
```

Check API health status and connectivity.

### Credential Management

#### List credentials

```bash
nexus credential list [--type TYPE] [--provider PROVIDER] [--status STATUS] [--format FORMAT]
```

Options:
- `--type`: Filter by credential type (e.g., aws_role, gcp_sa, github_token)
- `--provider`: Filter by provider (github, google, etc)
- `--status`: Filter by status (active, rotating, expired, revoked)
- `--format`: Output format (table, json) [default: table]

#### Get credential

```bash
nexus credential get ID [--format FORMAT]
```

Options:
- `ID`: Credential ID (required)
- `--format`: Output format (table, json) [default: json]

#### Create credential

```bash
nexus credential create --name NAME --type TYPE --provider PROVIDER [--config CONFIG] [--format FORMAT]
```

Options:
- `--name`: Credential name (required)
- `--type`: Credential type (required)
- `--provider`: Provider name (required)
- `--config`: Configuration as JSON string (optional)
- `--format`: Output format (table, json) [default: json]

Example:
```bash
nexus credential create \
  --name "AWS Prod" \
  --type aws_role \
  --provider github \
  --config '{"role_arn":"arn:aws:iam::123456789:role/gh","duration":3600}'
```

#### Delete credential

```bash
nexus credential delete ID [--force]
```

Options:
- `ID`: Credential ID (required)
- `--force`: Skip deletion confirmation

#### Rotate credential

```bash
nexus credential rotate ID [--force]
```

Options:
- `ID`: Credential ID (required)
- `--force`: Force immediate rotation (skips checks)

### Audit Trail

#### View audit log

```bash
nexus audit log [--limit LIMIT] [--offset OFFSET] [--resource-id ID] [--action ACTION]
```

Options:
- `--limit`: Number of events to return [default: 100]
- `--offset`: Pagination offset [default: 0]
- `--resource-id`: Filter by resource ID
- `--action`: Filter by action (ROTATE, CREATE, DELETE, etc)

## Examples

### Create AWS role credential

```bash
nexus credential create \
  --name "GitHub Actions AWS" \
  --type aws_role \
  --provider github \
  --config '{
    "role_arn": "arn:aws:iam::123456789012:role/github-actions",
    "duration_seconds": 3600,
    "external_id": "github-repo-id"
  }'
```

### List and filter by status

```bash
# Active credentials only
nexus credential list --status active

# Rotating credentials
nexus credential list --status rotating

# Expired credentials
nexus credential list --status expired
```

### Rotate all AWS credentials

```bash
nexus credential list --type aws_role --format json | while read -r cred; do
  ID=$(echo "$cred" | jq -r '.id')
  echo "Rotating $ID..."
  nexus credential rotate "$ID"
done
```

### Export audit trail to CSV

```bash
nexus audit log --limit 1000 --action ROTATE | \
  jq -r '.[] | "\(.timestamp),\(.action),\(.actor_id),\(.resource_id)"' | \
  tee audit_export.csv
```

### Monitor credential expirations

```bash
# Get all credentials expiring in next 7 days
nexus credential list --format json | jq '.[] | 
  select(.expires_at < now + 7*24*3600) | 
  {id, name, expires_at}'
```

## Troubleshooting

### Error: NEXUS_API_KEY not set

```
✗ NEXUS_API_KEY environment variable is required.
Get your API key from https://portal.nexusshield.cloud
```

**Solution:** Export your API key:
```bash
export NEXUS_API_KEY="your-api-key"
```

### Error: Connection refused

```
✗ Error checking health: Connection refused
```

**Solution:** Verify API URL is correct:
```bash
export NEXUS_API_URL="https://api.nexusshield.cloud"
```

### Error: Credential not found

```
✗ Credential not found: Not found
```

**Solution:** Verify credential ID exists:
```bash
nexus credential list | grep "your-credential-name"
```

### Timeout errors

**Solution:** Increase timeout:
```bash
export NEXUS_TIMEOUT=60  # 60 seconds
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NEXUS_API_KEY` | (required) | Bearer token for authentication |
| `NEXUS_API_URL` | https://api.nexusshield.cloud | API base URL |
| `NEXUS_TIMEOUT` | 30 | Request timeout in seconds |

## Exit Codes

- `0`: Success
- `1`: General error
- `130`: Interrupted by user (Ctrl+C)

## SDK Usage

The CLI uses the generated NexusShield Python SDK. To use the SDK in your own Python code:

```python
from nexusshield import create_client

client = create_client(api_key='your-api-key')

# List credentials
response = client.list_credentials(type='aws_role')
if response.is_success():
    for cred in response.data['credentials']:
        print(f"  {cred['name']}: {cred['status']}")

# Rotate credential
result = client.rotate_credential('cred_123')
print(f"Rotated at {result.data['rotated_at']}")
```

See [SDK README](../generated/python-sdk/README.md) for full SDK documentation.

## Support

- Documentation: https://nexusshield.cloud/docs
- Issues: https://github.com/nexusshield/cli/issues
- Support: support@nexusshield.cloud
