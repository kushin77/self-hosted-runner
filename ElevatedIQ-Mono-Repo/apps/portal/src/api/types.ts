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
  time: string;
  type: string;
  severity: 'info' | 'warn' | 'high' | 'critical';
  message: string;
  details?: string;
}

export interface BillingDTO {
  monthlyJobs: number;
  avgMinutesPerJob: number;
  gpuPercent: number;
  estimate: number;
}

export interface CacheLayerDTO {
  name: string;
  hitRate: number;
  sizeGB: string;
  items: number;
}

export interface AIInsightDTO {
  id: string;
  title: string;
  severity: string;
  category: string;
  description: string;
  recommendation: string;
}

// Additional API types used by the typed API client
export type APIRequestOptions = {
  timeout?: number;
  retries?: number;
  headers?: Record<string, string>;
};

export type APIResponse<T> = {
  data: T;
  status: number;
  timestamp: number;
};

export type APIError = { code?: string; message: string };

export type AuthToken = {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number;
  tokenType?: string;
};

export type Runner = {
  id: string;
  name: string;
  status?: string;
  labels?: string[];
  os?: string;
  arch?: string;
  uptime?: number;
  jobsCompleted?: number;
  lastJobTime?: number;
  createdAt?: number;
};

export type RunnerPool = { id: string; name: string; mode?: string; region?: string; runnerCount?: number };

export type RunnersResponse = { runners: Runner[]; pools?: RunnerPool[]; total?: number; page?: number; pageSize?: number };

export type Event = { id: string; type: string; timestamp: number; message?: string; runnerId?: string; severity?: string; metadata?: Record<string, any>; jobId?: string };

export type EventsResponse = { events: Event[]; total?: number; page?: number; pageSize?: number };

export type BillingResponse = { currentMonth?: any; history?: any[]; currency?: string };

export type CacheResponse = { metrics?: any; packages?: Record<string, any> };

export type AIResponse = { failureAnalyses?: any[]; insights?: any };
