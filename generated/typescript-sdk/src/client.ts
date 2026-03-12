/**
 * NexusShield SDK - TypeScript Client
 * Enterprise credential management, observability, and orchestration API
 * Version: 1.0.0
 */

import axios, {
  AxiosInstance,
  AxiosRequestConfig,
  AxiosResponse,
  AxiosError,
  InternalAxiosRequestConfig,
} from 'axios';

/**
 * API Response wrapper interface
 */
export interface APIResponse<T = any> {
  status: 'success' | 'error' | 'partial';
  data: T | null;
  error: ErrorPayload | null;
  metadata: ResponseMetadata;
}

export interface ErrorPayload {
  code: string;
  message: string;
  retryable: boolean;
  retryAfter?: number;
  details?: Record<string, any>;
}

export interface ResponseMetadata {
  requestId: string;
  timestamp: string;
  version: string;
  warnings?: string[];
}

/**
 * Authentication types
 */
export interface LoginRequest {
  provider: 'github' | 'google';
  code: string;
}

export interface LoginResponse {
  access_token: string;
  refresh_token: string;
  user: User;
}

export interface User {
  id: string;
  email: string;
  name: string;
  avatar_url?: string;
  created_at: string;
}

/**
 * Credential types
 */
export interface Credential {
  id: string;
  name: string;
  type: string;
  provider: string;
  status: 'active' | 'rotating' | 'expired' | 'revoked';
  expires_at?: string;
  created_at: string;
  updated_at: string;
  metadata?: Record<string, any>;
}

export interface CreateCredentialRequest {
  name: string;
  type: string;
  provider: string;
  config: Record<string, any>;
}

export interface RotateCredentialRequest {
  credential_id: string;
  force?: boolean;
}

export interface RotateCredentialResponse {
  credential_id: string;
  rotated_at: string;
  expires_at: string;
  status: string;
}

/**
 * Health check types
 */
export interface HealthStatus {
  status: 'ok' | 'degraded' | 'unhealthy';
  timestamp: string;
  uptime_seconds?: number;
  components?: {
    database: string;
    cache: string;
    external_services: string;
  };
}

/**
 * Request/Response configuration
 */
export interface ClientConfig {
  baseURL?: string;
  apiKey?: string;
  timeout?: number;
  maxRetries?: number;
  retryDelay?: number;
}

/**
 * NexusShield SDK Client
 */
export class NexusShieldClient {
  private client: AxiosInstance;
  private config: Required<ClientConfig>;

  constructor(config: ClientConfig = {}) {
    this.config = {
      baseURL: config.baseURL || 'https://api.nexusshield.cloud',
      apiKey: config.apiKey || process.env.NEXUS_API_KEY || '',
      timeout: config.timeout || 30000,
      maxRetries: config.maxRetries || 3,
      retryDelay: config.retryDelay || 1000,
    };

    this.client = axios.create({
      baseURL: this.config.baseURL,
      timeout: this.config.timeout,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'NexusShield-SDK/1.0.0-typescript',
      },
    });

    // Add request interceptor for API key
    this.client.interceptors.request.use((config: InternalAxiosRequestConfig) => {
      if (this.config.apiKey) {
        config.headers.Authorization = `Bearer ${this.config.apiKey}`;
      }
      return config;
    });

    // Add response interceptor for error handling
    this.client.interceptors.response.use(
      (response) => response,
      async (error: AxiosError) => {
        const config = error.config as InternalAxiosRequestConfig & { _retry?: number };
        config._retry = config._retry || 0;

        // Retry logic for transient errors
        if (
          config._retry < this.config.maxRetries &&
          error.response &&
          [429, 502, 503, 504].includes(error.response.status)
        ) {
          config._retry++;
          const delay = this.config.retryDelay * Math.pow(2, config._retry - 1);
          await new Promise((resolve) => setTimeout(resolve, delay));
          return this.client(config);
        }

        return Promise.reject(error);
      }
    );
  }

  /**
   * Health check endpoint
   */
  async getHealth(): Promise<APIResponse<HealthStatus>> {
    const response = await this.client.get<APIResponse<HealthStatus>>('/api/v1/health');
    return response.data;
  }

  /**
   * Authentication endpoints
   */
  async login(request: LoginRequest): Promise<APIResponse<LoginResponse>> {
    const response = await this.client.post<APIResponse<LoginResponse>>(
      '/api/v1/auth/login',
      request
    );
    return response.data;
  }

  async logout(): Promise<APIResponse<{ message: string }>> {
    const response = await this.client.post<APIResponse<{ message: string }>>(
      '/api/v1/auth/logout'
    );
    return response.data;
  }

  async getCurrentUser(): Promise<APIResponse<User>> {
    const response = await this.client.get<APIResponse<User>>('/api/v1/auth/me');
    return response.data;
  }

  /**
   * Credential management endpoints
   */
  async listCredentials(
    filter?: Record<string, any>
  ): Promise<APIResponse<{ credentials: Credential[]; total: number }>> {
    const response = await this.client.get<APIResponse<{ credentials: Credential[]; total: number }>>(
      '/api/v1/credentials',
      { params: filter }
    );
    return response.data;
  }

  async getCredential(id: string): Promise<APIResponse<Credential>> {
    const response = await this.client.get<APIResponse<Credential>>(
      `/api/v1/credentials/${id}`
    );
    return response.data;
  }

  async createCredential(request: CreateCredentialRequest): Promise<APIResponse<Credential>> {
    const response = await this.client.post<APIResponse<Credential>>(
      '/api/v1/credentials',
      request
    );
    return response.data;
  }

  async deleteCredential(id: string): Promise<APIResponse<{ message: string }>> {
    const response = await this.client.delete<APIResponse<{ message: string }>>(
      `/api/v1/credentials/${id}`
    );
    return response.data;
  }

  async rotateCredential(
    request: RotateCredentialRequest
  ): Promise<APIResponse<RotateCredentialResponse>> {
    const response = await this.client.post<APIResponse<RotateCredentialResponse>>(
      `/api/v1/credentials/${request.credential_id}/rotate`,
      { force: request.force }
    );
    return response.data;
  }

  /**
   * Audit/Observability endpoints
   */
  async getAuditLog(filters?: {
    limit?: number;
    offset?: number;
    resource_id?: string;
    action?: string;
    date_from?: string;
    date_to?: string;
  }): Promise<APIResponse<{ events: any[]; total: number }>> {
    const response = await this.client.get<APIResponse<{ events: any[]; total: number }>>(
      '/api/v1/audit',
      { params: filters }
    );
    return response.data;
  }

  /**
   * Utility methods
   */
  async request<T = any>(
    method: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH',
    url: string,
    data?: any,
    config?: AxiosRequestConfig
  ): Promise<APIResponse<T>> {
    const response = await this.client.request<APIResponse<T>>({
      method,
      url,
      data,
      ...config,
    });
    return response.data;
  }

  /**
   * Type-safe error handling
   */
  isRetryableError(error: unknown): boolean {
    if (error instanceof AxiosError) {
      const response = error.response?.data as APIResponse;
      return response?.error?.retryable || false;
    }
    return false;
  }

  /**
   * Get retry delay from API response
   */
  getRetryDelay(error: unknown): number {
    if (error instanceof AxiosError) {
      const response = error.response?.data as APIResponse;
      return response?.error?.retryAfter || this.config.retryDelay;
    }
    return this.config.retryDelay;
  }
}

/**
 * Export factory function for convenience
 */
export function createClient(config?: ClientConfig): NexusShieldClient {
  return new NexusShieldClient(config);
}

/**
 * Named exports for common types
 */
export default NexusShieldClient;
