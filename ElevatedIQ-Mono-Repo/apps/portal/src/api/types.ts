// Clean consolidated types for portal

export interface RunnerDTO {
  id: string;
  name: string;
  mode: 'managed' | 'byoc' | 'on-prem' | 'onprem';
  os: string;
  status: 'running' | 'idle' | 'provisioning' | 'draining' | 'error';
  cpu: number;
  mem: number;
  gpu?: number;
  currentJob?: string | null;
  pool?: string;
  lastHeartbeat?: string | number;
  [key: string]: any;
}

export interface EventDTO {
  time?: string;
  type?: string;
  severity?: 'info' | 'warn' | 'high' | 'critical';
  message?: string;
  details?: string;
  [key: string]: any;
}

export interface BillingDTO {
  monthlyJobs?: number;
  avgMinutesPerJob?: number;
  gpuPercent?: number;
  estimate?: number;
  [key: string]: any;
}

export interface CacheLayerDTO {
  name?: string;
  hitRate?: number;
  sizeGB?: string;
  items?: number;
  [key: string]: any;
}

export interface AIInsightDTO {
  id?: string;
  title?: string;
  severity?: string;
  category?: string;
  description?: string;
  recommendation?: string;
  [key: string]: any;
}

// Compatibility aliases used across the app
export type Runner = RunnerDTO;
export type RunnerPool = Runner[];
export type Event = EventDTO;
export type BillingResponse = BillingDTO;
export type CacheResponse = CacheLayerDTO;
export type AIResponse = AIInsightDTO[];

// Auth types
export interface AuthToken {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number;
  tokenType?: string;
}

export interface AuthContext {
  token?: AuthToken | null;
  isAuthenticated: boolean;
  expiresIn?: number;
}

// Generic API types
export interface APIError {
  message: string;
  code?: string | number;
}

export interface APIRequestOptions {
  method?: string;
  body?: any;
  headers?: Record<string, string>;
  timeout?: number;
  retries?: number;
}

export interface APIResponse<T = any> {
  data: T;
  error?: APIError | null;
  status?: number;
  timestamp?: number;
}

export interface RunnersResponse {
  runners: Runner[];
}

export interface EventsResponse {
  events: Event[];
}
