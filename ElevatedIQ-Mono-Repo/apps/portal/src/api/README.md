# API Integration Layer

RunnerCloud Portal API client with TypeScript types, auth handling, and mock server support.

## Structure

- `types.ts` - TypeScript interfaces for all API data structures
- `auth.ts` - Authentication manager with token rotation
- `client.ts` - Main API client with typed endpoints
- `mock.ts` - Mock API server for local development
- `index.ts` - Public exports

## Usage

### Basic API Calls

```typescript
import { apiClient } from '@/api';

// Get all runners
const runners = await apiClient.getRunners();

// Get events
const events = await apiClient.getEvents();

// Get billing info
const billing = await apiClient.getBilling();

// Get cache metrics
const cache = await apiClient.getCacheMetrics();

// Get AI insights
const insights = await apiClient.getAIInsights();
```

### Authentication

```typescript
import { authManager } from '@/api';

// Login with GitHub OAuth
const token = await apiClient.loginWithGitHub(code);
authManager.setToken(token);

// Get auth context
const context = authManager.getContext();
console.log(context.isAuthenticated); // true

// Subscribe to auth changes
const unsubscribe = authManager.subscribe(context => {
  console.log('Auth state changed:', context);
});

// Logout
await apiClient.logout();

// Cleanup
unsubscribe();
```

### Using Mock API for Development

Enable the mock API for local development without a backend:

```typescript
import { mockAPIServer, initMockAPI } from '@/api';

// Enable in console
localStorage.setItem('USE_MOCK_API', 'true');

// Or programmatically
mockAPIServer.enable();
initMockAPI();

// Now all /api/* calls will use mock data
const runners = await apiClient.getRunners(); // Returns mock data
```

**Mock Data Available:**
- 3 sample runners (Linux x64, ARM64, Windows)
- 2 runner pools with scaling config
- Event history (job completions, scaling)
- Billing metrics (current month + history)
- Cache statistics (npm, pip, Maven, Docker)
- AI failure analysis samples

### Custom Endpoints

Add new endpoints to `APIClient`:

```typescript
export class APIClient {
  async getCustomData(): Promise<CustomType> {
    return this.request<CustomType>('/custom-endpoint', {
      method: 'GET',
    }).then(res => res.data);
  }
}
```

## Features

### Authentication Manager
- Automatic token refresh 5 minutes before expiry
- Token persistence in localStorage
- Auth state change notifications
- Clean logout with token clearing

### API Client
- Automatic retry with exponential backoff
- Request timeout handling
- Auth header injection
- Structured error responses
- Request/response typing

### Error Handling

```typescript
try {
  const runners = await apiClient.getRunners();
} catch (error) {
  console.error('Failed to fetch runners:', error.message);
  // Handle error (display to user, etc.)
}
```

## Configuration

Set custom base URL:

```typescript
const client = new APIClient('https://api.example.com/v1');
```

Configure retry behavior:

```typescript
client.retryConfig = {
  maxRetries: 5,
  backoffMultiplier: 2,
  initialDelay: 1000,
};
```

## TypeScript Support

All API responses are fully typed:

```typescript
import type {
  Runner,
  RunnerPool,
  Event,
  BillingResponse,
  CacheResponse,
  AIResponse,
} from '@/api';

const runners: Runner[] = await apiClient.getRunners();
```

## Live Reload Demo

The mock API provides instant feedback for UI development. Start portal dev server:

```bash
cd ElevatedIQ-Mono-Repo/apps/portal
npm run dev

# In browser console:
localStorage.setItem('USE_MOCK_API', 'true');
location.reload();
```

Now all pages will use mock data instantly without backend setup.

## Future Enhancements

- [ ] WebSocket support for real-time events
- [ ] Request caching layer
- [ ] Request deduplication
- [ ] Offline support with service worker
- [ ] GraphQL migration (optional)
- [ ] OpenAPI code generation
