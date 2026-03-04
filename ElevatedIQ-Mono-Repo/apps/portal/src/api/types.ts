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
