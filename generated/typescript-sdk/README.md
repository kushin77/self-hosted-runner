# NexusShield TypeScript SDK

Enterprise credential management, observability, and orchestration API client for TypeScript/Node.js.

## Installation

```bash
npm install @nexusshield/sdk
# or
yarn add @nexusshield/sdk
```

## Quick Start

```typescript
import { createClient } from '@nexusshield/sdk';

// Create client with API key
const client = createClient({
  baseURL: 'https://api.nexusshield.cloud',
  apiKey: process.env.NEXUS_API_KEY,
});

// Get current user
const response = await client.getCurrentUser();
if (response.status === 'success') {
  console.log('Logged in as', response.data?.email);
}

// List all credentials
const credentials = await client.listCredentials();
console.log(`Found ${credentials.metadata.total} credentials`);

// Rotate a credential
const rotated = await client.rotateCredential({
  credential_id: 'cred_123',
  force: true,
});
console.log('Rotated at', rotated.data?.rotated_at);
```

## API Methods

### Authentication

- `login(provider, code)` - OAuth 2.0 login
- `logout()` - Logout current session
- `getCurrentUser()` - Get current user info

### Credential Management

- `listCredentials(filter?)` - List all credentials
- `getCredential(id)` - Get credential details
- `createCredential(request)` - Create new credential
- `deleteCredential(id)` - Delete credential
- `rotateCredential(request)` - Rotate credential

### System

- `getHealth()` - Get system health status

### Audit

- `getAuditLog(filters?)` - Get audit trail

## Error Handling

The SDK returns responses in the unified APIResponse format:

```typescript
interface APIResponse<T> {
  status: 'success' | 'error' | 'partial';
  data: T | null;
  error: ErrorPayload | null;
  metadata: ResponseMetadata;
}
```

Check return status to determine outcome:

```typescript
const response = await client.rotateCredential({...});

if (response.status === 'success') {
  console.log('Credential rotated:', response.data);
} else if (response.status === 'partial') {
  console.warn('Partial success:', response.data, 'Warnings:', response.metadata.warnings);
} else {
  console.error('Error:', response.error?.code, response.error?.message);
  if (response.error?.retryable) {
    // Retry after retryAfter milliseconds
    await new Promise(r => setTimeout(r, response.error.retryAfter || 5000));
  }
}
```

## Retry Behavior

The SDK automatically retries on:
- Rate limits (429)
- Server errors (502, 503, 504)

Exponential backoff is applied with configurable delays.

```typescript
const client = createClient({
  apiKey: process.env.NEXUS_API_KEY,
  maxRetries: 5,       // Max retry attempts
  retryDelay: 1000,    // Initial delay in ms
});
```

## Configuration

```typescript
interface ClientConfig {
  baseURL?: string;           // API base URL
  apiKey?: string;            // Bearer token
  timeout?: number;           // Request timeout in ms
  maxRetries?: number;        // Max retry attempts
  retryDelay?: number;        // Initial retry delay in ms
}
```

Environment variable fallback:
- API Key: `NEXUS_API_KEY` environment variable

## Examples

### List and filter credentials

```typescript
const response = await client.listCredentials({
  type: 'aws_role',
  provider: 'github',
});

console.log(`Found ${response.data?.credentials.length} AWS role credentials`);
```

###  Create a credential

```typescript
const newCred = await client.createCredential({
  name: 'Production AWS Role',
  type: 'aws_role',
  provider: 'github',
  config: {
    role_arn: 'arn:aws:iam::123456789:role/github-actions',
    duration_seconds: 3600,
  },
});

console.log('Created credential:', newCred.data?.id);
```

### Get audit trail

```typescript
const audit = await client.getAuditLog({
  limit: 100,
  resource_id: 'cred_123',
  action: 'ROTATE',
  date_from: '2024-01-01T00:00:00Z',
});

console.log(`${audit.data?.total} audit events found`);
audit.data?.events.forEach(event => {
  console.log(`${event.timestamp}: ${event.action} by ${event.actor_id}`);
});
```

## Type Safety

Full TypeScript support with exported types:

```typescript
import {
  NexusShieldClient,
  Credential,
  APIResponse,
  ClientConfig,
} from '@nexusshield/sdk';

const client = new NexusShieldClient({/* ... */});
const response: APIResponse<Credential> = await client.getCredential('cred_123');
```

## License

Apache 2.0
