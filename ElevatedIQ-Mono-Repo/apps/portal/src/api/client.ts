/**
 * API Client
 * Main client for communicating with RunnerCloud backend
 */

import { authManager } from './auth';
import { initMockAPI, mockAPIServer } from './mock';
import type {
  APIError,
  APIRequestOptions,
  APIResponse,
  AuthToken,
  BillingResponse,
  CacheResponse,
  EventsResponse,
  RunnersResponse,
  AIResponse,
} from './types';

export class APIClient {
  private baseURL: string;
  private defaultTimeout: number = 30000; // 30s
  private retryConfig = {
    maxRetries: 3,
    backoffMultiplier: 2,
    initialDelay: 1000,
  };

  constructor(baseURL: string = '/api') {
    this.baseURL = baseURL;
  }

  /**
   * Make HTTP request with auth, retry, and error handling
   */
  private async request<T>(
    endpoint: string,
    options: RequestInit & APIRequestOptions = {}
  ): Promise<APIResponse<T>> {
    const url = `${this.baseURL}${endpoint}`;
    const timeout = options.timeout ?? this.defaultTimeout;
    const retries = options.retries ?? this.retryConfig.maxRetries;

    let lastError: Error | null = null;

    for (let attempt = 0; attempt <= retries; attempt++) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), timeout);

        const headers: HeadersInit = {
          'Content-Type': 'application/json',
          ...authManager.getAuthHeader(),
          ...options.headers,
        };

        const response = await fetch(url, {
          ...options,
          headers,
          signal: controller.signal,
        });

        clearTimeout(timeoutId);

        if (response.ok) {
          const data = await response.json();
          return {
            data,
            status: response.status,
            timestamp: Date.now(),
          };
        }

        if (response.status === 401) {
          // Unauthorized - refresh token
          await authManager.refreshToken();
          if (attempt < retries) {
            continue; // Retry with new token
          }
        }

        if (response.status >= 500 && attempt < retries) {
          // Server error - retry
          const delay = this.retryConfig.initialDelay * Math.pow(this.retryConfig.backoffMultiplier, attempt);
          await new Promise(resolve => setTimeout(resolve, delay));
          continue;
        }

        const error = await response.json() as APIError;
        throw new Error(`API Error: ${error.message} (${error.code})`);
      } catch (error) {
        lastError = error as Error;

        if (attempt < retries) {
          const delay = this.retryConfig.initialDelay * Math.pow(this.retryConfig.backoffMultiplier, attempt);
          await new Promise(resolve => setTimeout(resolve, delay));
          continue;
        }

        break;
      }
    }

    throw lastError ?? new Error('Request failed after retries');
  }

  // ====== Runners Endpoints ======

  /**
   * Get all runners and pools
   */
  async getRunners(page = 1, pageSize = 50): Promise<RunnersResponse> {
    return this.request<RunnersResponse>(`/runners?page=${page}&pageSize=${pageSize}`, {
      method: 'GET',
    }).then(res => res.data);
  }

  /**
   * Get runner by ID
   */
  async getRunner(id: string) {
    return this.request(`/runners/${id}`, {
      method: 'GET',
    }).then(res => res.data);
  }

  /**
   * Create new runner pool
   */
  async createRunnerPool(poolConfig: Record<string, unknown>) {
    return this.request('/runners/pools', {
      method: 'POST',
      body: JSON.stringify(poolConfig),
    }).then(res => res.data);
  }

  // ====== Events Endpoints ======

  /**
   * Get events stream (paginated for now, WebSocket in future)
   */
  async getEvents(page = 1, pageSize = 100): Promise<EventsResponse> {
    return this.request<EventsResponse>(`/events?page=${page}&pageSize=${pageSize}`, {
      method: 'GET',
    }).then(res => res.data);
  }

  /**
   * Get events for specific runner
   */
  async getRunnerEvents(runnerId: string, page = 1, pageSize = 50) {
    return this.request(`/events?runnerId=${runnerId}&page=${page}&pageSize=${pageSize}`, {
      method: 'GET',
    }).then(res => res.data);
  }

  // ====== Billing Endpoints ======

  /**
   * Get billing information
   */
  async getBilling(): Promise<BillingResponse> {
    return this.request<BillingResponse>('/billing', {
      method: 'GET',
    }).then(res => res.data);
  }

  /**
   * Get usage for specific date range
   */
  async getBillingUsage(startDate: string, endDate: string) {
    return this.request(`/billing/usage?startDate=${startDate}&endDate=${endDate}`, {
      method: 'GET',
    }).then(res => res.data);
  }

  // ====== Cache Endpoints ======

  /**
   * Get cache metrics
   */
  async getCacheMetrics(): Promise<CacheResponse> {
    return this.request<CacheResponse>('/cache/metrics', {
      method: 'GET',
    }).then(res => res.data);
  }

  /**
   * Invalidate cache for specific package manager
   */
  async invalidateCache(packageManager: string) {
    return this.request(`/cache/invalidate/${packageManager}`, {
      method: 'POST',
    }).then(res => res.data);
  }

  // ====== AI Endpoints ======

  /**
   * Get AI failure insights
   */
  async getAIInsights(): Promise<AIResponse> {
    return this.request<AIResponse>('/ai/insights', {
      method: 'GET',
    }).then(res => res.data);
  }

  /**
   * Get failure analysis for job
   */
  async analyzeJobFailure(jobId: string) {
    return this.request(`/ai/analyze/${jobId}`, {
      method: 'GET',
    }).then(res => res.data);
  }

  // ====== Auth Endpoints ======

  /**
   * Login with credentials
   */
  async login(email: string, password: string): Promise<AuthToken> {
    return this.request<AuthToken>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }).then(res => res.data);
  }

  /**
   * Login with GitHub OAuth
   */
  async loginWithGitHub(code: string): Promise<AuthToken> {
    return this.request<AuthToken>('/auth/github', {
      method: 'POST',
      body: JSON.stringify({ code }),
    }).then(res => res.data);
  }

  /**
   * Logout
   */
  async logout(): Promise<void> {
    await this.request('/auth/logout', {
      method: 'POST',
    });
    authManager.clearToken();
  }
}

// Singleton instance
// Read Vite env overrides when available
const API_BASE = typeof import.meta !== 'undefined' && (import.meta as any).env && (import.meta as any).env.VITE_API_BASE
  ? String((import.meta as any).env.VITE_API_BASE)
  : '';
const USE_MOCK = typeof import.meta !== 'undefined' && (import.meta as any).env && (import.meta as any).env.VITE_API_USE_MOCK !== 'false';

export const apiClient = new APIClient(API_BASE || '/api');

// If developer requested in-Vite mock behavior, enable mock API intercepts
if (USE_MOCK) {
  try {
    // Enable mock server flag and initialize fetch interception
    mockAPIServer.enable();
    initMockAPI();
    // eslint-disable-next-line no-console
    console.info('Portal API: initialized in-client mock API (USE_MOCK=true)');
  } catch (e) {
    // eslint-disable-next-line no-console
    console.warn('Portal API: failed to initialize mock API', e);
  }
}
