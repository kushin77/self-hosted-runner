/**
 * NexusShield API Client Service
 * 
 * Ephemeral credential management - runtime fetch only, no caching
 * Idempotent operations - all requests are re-executable
 * Full OAuth 2.0 + JWT authentication support
 */

const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:3000';
const API_VERSION = '/api/v1';

interface FetchOptions {
  method?: string;
  body?: any;
  headers?: Record<string, string>;
}

/**
 * Make authenticated API request
 * All requests are idempotent and may be retried safely
 */
async function apiRequest<T>(
  endpoint: string,
  options: FetchOptions = {},
  token?: string
): Promise<T> {
  const url = `${API_BASE}${API_VERSION}${endpoint}`;
  
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...options.headers,
  };

  // Add ephemeral auth token (runtime fetch, no persistence)
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const fetchOptions: RequestInit = {
    method: options.method || 'GET',
    headers,
  };

  if (options.body) {
    fetchOptions.body = JSON.stringify(options.body);
  }

  const response = await fetch(url, fetchOptions);

  if (!response.ok) {
    throw new Error(`API Error: ${response.status} ${response.statusText}`);
  }

  return response.json();
}

// =========================================================================
// CREDENTIAL SERVICE - 4-LAYER EPHEMERAL RESOLUTION
// =========================================================================

export const CredentialAPI = {
  /**
   * List all credentials (idempotent)
   * Safe to call multiple times - will return same result
   */
  async listCredentials(token?: string) {
    return apiRequest<{ credentials: any[] }>(
      '/credentials',
      { method: 'GET' },
      token
    );
  },

  /**
   * Get single credential (idempotent)
   */
  async getCredential(credentialId: string, token?: string) {
    return apiRequest<{ credential: any }>(
      `/credentials/${credentialId}`,
      { method: 'GET' },
      token
    );
  },

  /**
   * Rotate credential immediately
   * Immutable: Returns immutable rotation record
   */
  async rotateCredential(credentialId: string, token?: string) {
    return apiRequest<{ rotationId: string; rotatedAt: string }>(
      `/credentials/${credentialId}/rotate`,
      { method: 'POST' },
      token
    );
  },

  /**
   * Get credential rotation history
   * Immutable: All history preserved, append-only
   */
  async getRotationHistory(credentialId: string, token?: string) {
    return apiRequest<{ rotations: any[] }>(
      `/credentials/${credentialId}/rotations`,
      { method: 'GET' },
      token
    );
  },
};

// =========================================================================
// AUDIT SERVICE - IMMUTABLE APPEND-ONLY LOG
// =========================================================================

export const AuditAPI = {
  /**
   * Query audit trail (idempotent)
   * Filter parameters make it deterministic - same filters = same results
   */
  async queryAudit(
    filters: {
      limit?: number;
      offset?: number;
      resource_type?: string;
      action?: string;
      start_time?: string;
      end_time?: string;
    } = {},
    token?: string
  ) {
    const params = new URLSearchParams();
    if (filters.limit) params.append('limit', filters.limit.toString());
    if (filters.offset) params.append('offset', filters.offset?.toString() || '0');
    if (filters.resource_type) params.append('resource_type', filters.resource_type);
    if (filters.action) params.append('action', filters.action);
    if (filters.start_time) params.append('start_time', filters.start_time);
    if (filters.end_time) params.append('end_time', filters.end_time);

    return apiRequest<{ entries: any[]; total: number }>(
      `/audit?${params.toString()}`,
      { method: 'GET' },
      token
    );
  },

  /**
   * Verify audit trail integrity
   * Checks hash chain - detects any tampering
   */
  async verifyIntegrity(token?: string) {
    return apiRequest<{ isValid: boolean; entriesChecked: number; brokenChainAt?: string }>(
      '/audit/verify',
      { method: 'POST' },
      token
    );
  },

  /**
   * Export audit logs to cloud (immutable JSONL snapshot)
   */
  async exportToCloud(token?: string) {
    return apiRequest<{ exportId: string; cloudLocation: string; entryCount: number }>(
      '/audit/export',
      { method: 'POST' },
      token
    );
  },
};

// =========================================================================
// METRICS SERVICE - PROMETHEUS OBSERVABILITY
// =========================================================================

export const MetricsAPI = {
  /**
   * Get system metrics (idempotent)
   * Returns Prometheus text format
   */
  async getMetrics(token?: string) {
    const response = await fetch(
      `${API_BASE}/metrics`,
      token ? { headers: { Authorization: `Bearer ${token}` } } : {}
    );
    if (!response.ok) throw new Error('Failed to fetch metrics');
    return response.text(); // Prometheus format
  },

  /**
   * Get health check status
   * Used for liveness/readiness probes
   */
  async getHealth(token?: string) {
    return apiRequest<{
      status: 'healthy' | 'degraded' | 'unhealthy';
      checks: Record<string, string>;
      uptime_seconds: number;
    }>(
      '/health',
      { method: 'GET' },
      token
    );
  },
};

// =========================================================================
// COMPLIANCE SERVICE - POLICY & VALIDATION
// =========================================================================

export const ComplianceAPI = {
  /**
   * Get compliance status
   * Shows violations, policy adherence, rotation compliance
   */
  async getStatus(token?: string) {
    return apiRequest<{
      totalViolations: number;
      criticalViolations: number;
      complianceScore: number;
      policies: any[];
    }>(
      '/compliance/status',
      { method: 'GET' },
      token
    );
  },

  /**
   * Create compliance policy (idempotent upsert)
   * Same policy name = update existing
   */
  async createPolicy(policy: any, token?: string) {
    return apiRequest<{ policyId: string; created: boolean }>(
      '/compliance/policies',
      { method: 'POST', body: policy },
      token
    );
  },
};

// =========================================================================
// AUTHENTICATION SERVICE - OAUTH 2.0 & JWT
// =========================================================================

export const AuthAPI = {
  /**
   * Initiate OAuth 2.0 flow
   * Returns authorization URL
   */
  async initiateOAuth(provider: 'google' | 'github') {
    return apiRequest<{ authUrl: string }>(
      `/auth/${provider}`,
      { method: 'POST' }
    );
  },

  /**
   * Complete OAuth callback (idempotent)
   * Same code = same result
   */
  async completeOAuthCallback(provider: string, code: string) {
    return apiRequest<{ token: string; expiresIn: number; refreshToken: string }>(
      `/auth/${provider}/callback`,
      { method: 'POST', body: { code } }
    );
  },

  /**
   * Refresh JWT token
   * Ephemeral - new token every call
   */
  async refreshToken(refreshToken: string) {
    return apiRequest<{ token: string; expiresIn: number }>(
      '/auth/refresh',
      { method: 'POST', body: { refreshToken } }
    );
  },

  /**
   * Logout user
   * Idempotent - same result whether already logged out or not
   */
  async logout(token?: string) {
    return apiRequest<{ status: string }>(
      '/auth/logout',
      { method: 'POST' },
      token
    );
  },
};

// =========================================================================
// EXPORT ALL SERVICES
// =========================================================================

export const API = {
  Credentials: CredentialAPI,
  Audit: AuditAPI,
  Metrics: MetricsAPI,
  Compliance: ComplianceAPI,
  Auth: AuthAPI,
};

export default API;
