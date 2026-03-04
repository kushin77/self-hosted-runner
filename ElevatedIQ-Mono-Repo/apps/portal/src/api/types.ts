/**
 * API Types and Interfaces for RunnerCloud Portal
 */

// Auth & Tokens
export interface AuthToken {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  tokenType: 'Bearer';
}

export interface AuthContext {
  token: AuthToken | null;
  isAuthenticated: boolean;
  expiresIn: number;
}

// Runners
export interface Runner {
  id: string;
  name: string;
  status: 'idle' | 'busy' | 'terminating' | 'error';
  labels: string[];
  os: 'linux' | 'windows' | 'macos';
  arch: 'x64' | 'arm64';
  uptime: number; // seconds
  jobsCompleted: number;
  lastJobTime: number; // unix timestamp
  createdAt: number;
}

export interface RunnerPool {
  id: string;
  name: string;
  mode: 'managed' | 'byoc' | 'on-prem';
  region?: string;
  runnerCount: number;
  idleCount: number;
  busyCount: number;
  config: Record<string, unknown>;
}

export interface RunnersResponse {
  runners: Runner[];
  pools: RunnerPool[];
  total: number;
  page: number;
  pageSize: number;
}

// Events
export interface Event {
  id: string;
  type: 'runner_created' | 'runner_failed' | 'job_started' | 'job_completed' | 'job_failed' | 'scaling_event';
  timestamp: number;
  runnerId?: string;
  jobId?: string;
  message: string;
  severity: 'info' | 'warning' | 'error';
  metadata?: Record<string, unknown>;
}

export interface EventsResponse {
  events: Event[];
  total: number;
  page: number;
  pageSize: number;
}

// Billing
export interface BillingUsage {
  date: string;
  runners: number;
  computeHours: number;
  cacheHits: number;
  cacheBytes: number;
  cost: number; // USD
}

export interface BillingResponse {
  currentMonth: {
    runnerMinutes: number;
    cacheHits: number;
    estimatedCost: number;
  };
  history: BillingUsage[];
  currency: 'USD' | 'EUR' | 'GBP';
}

// Cache
export interface CacheMetrics {
  hitRate: number; // 0-100
  missRate: number;
  totalSize: number; // bytes
  itemCount: number;
  lastInvalidation: number; // unix timestamp
}

export interface CacheResponse {
  metrics: CacheMetrics;
  packages: {
    npm?: { hits: number; misses: number; size: number };
    pip?: { hits: number; misses: number; size: number };
    maven?: { hits: number; misses: number; size: number };
    docker?: { hits: number; misses: number; size: number };
  };
}

// AI Insights
export interface FailureAnalysis {
  jobId: string;
  rootCause: string;
  confidence: number; // 0-100
  fileReference?: string;
  suggestedFix: string;
  relatedIssues: { id: string; title: string }[];
  timestamp: number;
}

export interface AIResponse {
  failureAnalyses: FailureAnalysis[];
  insights: {
    failureRate: number;
    averageResolutionTime: number;
    topFailureCategories: string[];
  };
}

// API Error
export interface APIError {
  code: string;
  message: string;
  details?: Record<string, unknown>;
  statusCode: number;
}

// API Request/Response Options
export interface APIRequestOptions {
  headers?: Record<string, string>;
  timeout?: number;
  retries?: number;
}

export interface APIResponse<T> {
  data: T;
  status: number;
  timestamp: number;
}
