export interface RunnerDTO {
  id: string;
  name: string;
  mode: 'managed' | 'byoc' | 'on-prem';
  os: string;
  status: 'running' | 'idle' | 'provisioning' | 'draining';
  cpu: number;
  mem: number;
  gpu?: number;
  currentJob?: string | null;
  pool?: string;
  lastHeartbeat?: string;
}

export interface EventDTO {
  // Flexible event shape used across the app and mocks
  id?: string;
  time?: string;
  timestamp?: number | string;
  type?: string;
  severity?: 'info' | 'warn' | 'high' | 'critical' | string;
  message?: string;
  details?: string;
  runnerId?: string;
  jobId?: string;
  metadata?: Record<string, any>;
}

export interface BillingDTO {
  // Accept flexible billing shapes returned by mock and API
  currentMonth?: Record<string, any>;
  history?: Record<string, any>[];
  monthlyJobs?: number;
  avgMinutesPerJob?: number;
  gpuPercent?: number;
  estimate?: number;
  currency?: string;
}

export interface CacheLayerDTO {
  // Flexible cache metrics object
  name?: string;
  hitRate?: number;
  sizeGB?: string | number;
  items?: number;
  metrics?: Record<string, any>;
  packages?: Record<string, any>;
}

export interface AIInsightDTO {
  // Flexible AI insight shape
  id?: string;
  title?: string;
  severity?: string;
  category?: string;
  description?: string;
  recommendation?: string;
  jobId?: string;
  confidence?: number;
  fileReference?: string;
  suggestedFix?: string;
  relatedIssues?: Array<{ id: string; title: string }>;
  timestamp?: number;
}

// API client compatible types
export interface APIError {
  message: string;
  code?: string | number;
}

export interface APIRequestOptions extends RequestInit {
  timeout?: number;
  retries?: number;
}

export interface APIResponse<T> {
  data: T;
  status: number;
  timestamp: number;
}

export interface AuthToken {
  accessToken: string;
  tokenType?: string;
  refreshToken?: string;
  expiresAt: number;
}

export interface AuthContext {
  token: AuthToken | null;
  isAuthenticated: boolean;
  expiresIn: number;
}

export type BillingResponse = BillingDTO;
export type CacheResponse = CacheLayerDTO[];
export type EventsResponse = EventDTO[];
export type Event = EventDTO;
export type RunnersResponse = RunnerDTO[];
export type AIResponse = AIInsightDTO[];

// Compatibility aliases expected by some modules/mocks
export type Runner = RunnerDTO;
export interface RunnerPool {
  id?: string;
  name?: string;
  mode?: string;
  region?: string;
  runnerCount?: number;
  idleCount?: number;
  busyCount?: number;
  config?: Record<string, any>;
}
