/**
 * Mock API Server
 * Provides sample data for local development
 * Enable with: localStorage.setItem('USE_MOCK_API', 'true')
 */

// Local lightweight Runner/Pool shapes used only inside this mock module
// (intentionally minimal mock module - avoid importing strict DTOs to reduce
// coupling with upstream API types during local development)

const MOCK_RUNNERS = [
  {
    id: 'runner-1',
    name: 'ubuntu-x64-1',
    status: 'busy',
    labels: ['ubuntu-latest', 'x64'],
    os: 'linux',
    arch: 'x64',
    uptime: 3600,
    jobsCompleted: 42,
    lastJobTime: Date.now() - 60000,
    createdAt: Date.now() - 86400000,
  },
  {
    id: 'runner-2',
    name: 'ubuntu-arm64-1',
    status: 'idle',
    labels: ['ubuntu-latest', 'arm64'],
    os: 'linux',
    arch: 'arm64',
    uptime: 7200,
    jobsCompleted: 28,
    lastJobTime: Date.now() - 300000,
    createdAt: Date.now() - 86400000,
  },
  {
    id: 'runner-3',
    name: 'windows-x64-1',
    status: 'idle',
    labels: ['windows-latest', 'x64'],
    os: 'windows',
    arch: 'x64',
    uptime: 1800,
    jobsCompleted: 15,
    lastJobTime: Date.now() - 600000,
    createdAt: Date.now() - 43200000,
  },
];

const MOCK_POOLS = [
  {
    id: 'pool-1',
    name: 'Linux x64 Production',
    mode: 'managed',
    region: 'us-east-1',
    runnerCount: 5,
    idleCount: 2,
    busyCount: 3,
    config: { minRunners: 2, maxRunners: 10 },
  },
  {
    id: 'pool-2',
    name: 'ARM64 Builders',
    mode: 'managed',
    region: 'us-west-2',
    runnerCount: 3,
    idleCount: 2,
    busyCount: 1,
    config: { minRunners: 1, maxRunners: 5 },
  },
];

const MOCK_EVENTS = [
  {
    id: 'event-1',
    type: 'job_completed',
    timestamp: Date.now() - 30000,
    runnerId: 'runner-1',
    jobId: 'job-123',
    message: 'Job completed successfully in 4m 30s',
    severity: 'info',
  },
  {
    id: 'event-2',
    type: 'runner_created',
    timestamp: Date.now() - 120000,
    runnerId: 'runner-3',
    message: 'New Windows runner provisioned',
    severity: 'info',
  },
  {
    id: 'event-3',
    type: 'scaling_event',
    timestamp: Date.now() - 300000,
    message: 'Scaled up Linux x64 pool from 3 to 5 runners',
    severity: 'info',
    metadata: { poolId: 'pool-1', from: 3, to: 5 },
  },
];

const MOCK_BILLING = {
  currentMonth: {
    runnerMinutes: 15420,
    cacheHits: 8234,
    estimatedCost: 342.15,
  },
  history: [
    {
      date: new Date(Date.now() - 86400000).toISOString().split('T')[0],
      runners: 8,
      computeHours: 45.2,
      cacheHits: 1200,
      cacheBytes: 5368709120,
      cost: 52.4,
    },
    {
      date: new Date(Date.now() - 172800000).toISOString().split('T')[0],
      runners: 10,
      computeHours: 68.5,
      cacheHits: 2100,
      cacheBytes: 8589934592,
      cost: 78.9,
    },
  ],
  currency: 'USD',
};

const MOCK_CACHE = {
  metrics: {
    hitRate: 87.3,
    missRate: 12.7,
    totalSize: 47483648000,
    itemCount: 12847,
    lastInvalidation: Date.now() - 3600000,
  },
  packages: {
    npm: { hits: 3200, misses: 450, size: 15728640000 },
    pip: { hits: 2100, misses: 300, size: 10737418240 },
    maven: { hits: 1800, misses: 200, size: 12884901888 },
    docker: { hits: 1134, misses: 250, size: 8132830592 },
  },
};

const MOCK_AI = {
  failureAnalyses: [
    {
      jobId: 'job-456',
      rootCause: 'Missing environment variable',
      confidence: 95,
      fileReference: '.github/workflows/ci.yml:42',
      suggestedFix: 'Add NODE_ENV=production to job env or GitHub secrets',
      relatedIssues: [
        { id: 'issue-12', title: 'Environment setup for Node builds' },
      ],
      timestamp: Date.now() - 7200000,
    },
  ],
  insights: {
    failureRate: 4.2,
    averageResolutionTime: 45,
    topFailureCategories: [
      'Dependency resolution',
      'Missing environment variables',
      'Network timeouts',
    ],
  },
};

/**
 * Mock API Server with request handlers
 */
export class MockAPIServer {
  private enabled: boolean;
  private streamTimer?: number | null;
  private streamSubscribers: Set<(ev: any) => void> = new Set();

  constructor() {
    this.enabled = typeof localStorage !== 'undefined' && localStorage.getItem('USE_MOCK_API') === 'true';
  }

  /**
   * Check if mock server is enabled
   */
  isEnabled(): boolean {
    return this.enabled;
  }

  /**
   * Enable mock server
   */
  enable(): void {
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem('USE_MOCK_API', 'true');
      this.enabled = true;
    }
  }

  /**
   * Disable mock server
   */
  disable(): void {
    if (typeof localStorage !== 'undefined') {
      localStorage.removeItem('USE_MOCK_API');
      this.enabled = false;
    }
  }

  /**
   * Start a faux event stream. Calls subscriber callbacks periodically.
   * Returns an unsubscribe function.
   */
  startEventStream(subscriber: (ev: Event) => void, intervalMs = 1500): () => void {
    if (!this.enabled) {
      return () => {};
    }

    this.streamSubscribers.add(subscriber);

    // If timer already running, just return unsubscribe
    if (this.streamTimer) {
      return () => this.streamSubscribers.delete(subscriber);
    }

    // Start periodic emitter
    this.streamTimer = window.setInterval(() => {
      if (this.streamSubscribers.size === 0) {
        return;
      }

      // Rotate through existing mock events and also sometimes fabricate new ones
      const base = MOCK_EVENTS[Math.floor(Math.random() * MOCK_EVENTS.length)];
      const event = {
        ...base,
        id: `evt-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
        timestamp: Date.now(),
      } as any;

      this.streamSubscribers.forEach(cb => {
        try {
          cb(event);
        } catch (e) {
          // swallow subscriber errors
          // eslint-disable-next-line no-console
          console.warn('mock event subscriber threw', e);
        }
      });
    }, intervalMs) as unknown as number;

    return () => {
      this.streamSubscribers.delete(subscriber);
      if (this.streamSubscribers.size === 0 && this.streamTimer) {
        clearInterval(this.streamTimer as number);
        this.streamTimer = null;
      }
    };
  }

  /**
   * Handle request
   */
  handleRequest(url: string, options: RequestInit): Response | null {
    if (!this.enabled) {
      return null;
    }

    const urlObj = new URL(url, window.location.origin);
    const path = urlObj.pathname;
    const method = options.method || 'GET';

    // Simulate network delay (kept small during mocks)

    // Route handlers
    if (path === '/api/runners' && method === 'GET') {
      return this.createResponse({
        runners: MOCK_RUNNERS,
        pools: MOCK_POOLS,
        total: MOCK_RUNNERS.length,
        page: 1,
        pageSize: 50,
      });
    }

    if (path === '/api/events' && method === 'GET') {
      return this.createResponse({
        events: MOCK_EVENTS,
        total: MOCK_EVENTS.length,
        page: 1,
        pageSize: 100,
      });
    }

    if (path === '/api/billing' && method === 'GET') {
      return this.createResponse(MOCK_BILLING);
    }

    if (path === '/api/cache/metrics' && method === 'GET') {
      return this.createResponse(MOCK_CACHE);
    }

    if (path === '/api/ai/insights' && method === 'GET') {
      return this.createResponse(MOCK_AI);
    }

    if (path === '/api/auth/login' && method === 'POST') {
      const token = {
        accessToken: 'mock_token_' + Date.now(),
        refreshToken: 'mock_refresh_' + Date.now(),
        expiresAt: Date.now() + 3600000,
        tokenType: 'Bearer',
      };
      return this.createResponse(token);
    }

    return null;
  }

  /**
   * Create mock response
   */
  private createResponse(data: unknown, status = 200): Response {
    return new Response(JSON.stringify(data), {
      status,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

// Singleton instance
export const mockAPIServer = new MockAPIServer();

/**
 * Initialize mock API intercept
 */
export function initMockAPI(): void {
  if (!mockAPIServer.isEnabled()) {
    return;
  }

  const originalFetch = window.fetch;

  window.fetch = function (...args: Parameters<typeof fetch>): ReturnType<typeof fetch> {
    const [url, options] = args;
    const urlStr = typeof url === 'string' ? url : url.toString();

    if (urlStr.includes('/api/')) {
      const response = mockAPIServer.handleRequest(urlStr, options || {});
      if (response) {
        return Promise.resolve(response);
      }
    }

    return originalFetch.apply(window, args);
  } as typeof fetch;
}

/**
 * Convenience export to start the mock event stream from code or console.
 */
export function startMockEventStream(subscriber: (ev: Event) => void, intervalMs = 1500): () => void {
  return mockAPIServer.startEventStream(subscriber, intervalMs);
}

// Expose a simple global helper in dev for manual testing via console.
if (typeof window !== 'undefined') {
  (window as any).__runnercloud_mock_event_stream = (cb: (ev: any) => void, intervalMs = 1500) =>
    startMockEventStream(cb, intervalMs);
}
