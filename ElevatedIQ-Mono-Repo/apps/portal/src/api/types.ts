// API and DTO types for portal app

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

// Canonical app-level types / aliases
export type Runner = RunnerDTO;
export type RunnerPool = { id?: string; name?: string; runners?: Runner[] } | any;
export type Event = EventDTO;
export type BillingResponse = BillingDTO;
export type CacheResponse = CacheLayerDTO;
export type AIResponse = AIInsightDTO[];

// Auth types
export interface AuthToken {
  accessToken?: string;
  refreshToken?: string;
  expiresAt?: number;
  tokenType?: string;
  [key: string]: any;
}

export interface AuthContext {
  token?: AuthToken | null;
  isAuthenticated?: boolean;
  expiresIn?: number;
}

// Generic API types
export interface APIError {
  message: string;
  code?: string | number;
  [key: string]: any;
}

export interface APIRequestOptions {
  method?: string;
  body?: any;
  headers?: Record<string, string>;
  timeout?: number;
  retries?: number;
}

export interface APIResponse<T = any> {
  data?: T;
  error?: APIError | null;
  status?: number;
  timestamp?: number;
}

export type EventsResponse = { events?: Event[]; items?: Event[]; page?: number; total?: number };
export type RunnersResponse = { runners?: Runner[]; items?: Runner[]; page?: number; total?: number } | Runner[];

export type AuthTokenShape = AuthToken;
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

// Common aliases expected by other modules
export type Runner = RunnerDTO;
export type RunnerPool = { id?: string; name?: string; runners?: Runner[] };
export type Event = EventDTO;
export type BillingResponse = BillingDTO;
export type CacheResponse = CacheLayerDTO;
export type AIResponse = AIInsightDTO[];

export interface APIError {
  code?: string;
  message: string;
  [key: string]: any;
}

export interface APIRequestOptions {
  timeout?: number;
  retries?: number;
  headers?: Record<string, string>;
}

export interface APIResponse<T = any> {
  data: T;
  status: number;
  timestamp: number;
}

export type EventsResponse = { items: Event[]; page?: number; total?: number };
export type RunnersResponse = { items: Runner[]; page?: number; total?: number } | Runner[];

export type AuthToken = { token: string; expiresAt?: number };
export type AuthContext = { user?: string } | any;


// Compatibility aliases used across the app
export type Runner = RunnerDTO;
export type RunnerPool = Runner[];
export type Event = EventDTO;
export type BillingResponse = BillingDTO;
export type CacheResponse = CacheLayerDTO;
export type AIResponse = AIInsightDTO;

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

export interface APIError {
  message: string;
  code?: string | number;
}

export interface APIRequestOptions {
  method?: string;
  body?: any;
  headers?: Record<string, string>;
}

export interface APIResponse<T = any> {
  data?: T;
  error?: APIError | null;
}

export interface RunnersResponse {
  runners: Runner[];
}

export interface EventsResponse {
  events: Event[];
}
