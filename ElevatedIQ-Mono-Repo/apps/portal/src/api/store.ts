import { create } from 'zustand';

export interface MetricsSummary {
  uptime: string;
  jobs: {
    processed: number;
    succeeded: number;
    failed: number;
    duplicated: number;
    successRate: string;
  };
  queue: {
    depth: number;
    activeJobs: number;
  };
  latency: {
    lastJob_ms: number;
    job_p50_ms: number;
    job_p95_ms: number;
    job_p99_ms: number;
    terraform_p50_ms: number;
    terraform_p95_ms: number;
  };
  health: {
    vaultConnected: boolean;
    jobstoreOperational: boolean;
  };
  lastJobCompleted: string | null;
}

export interface Runner {
  id: string;
  name: string;
  status: 'online' | 'offline' | 'busy' | 'idle';
  labels: string[];
  cpu: number;
  memory: number;
  disk: number;
  jobsCompleted: number;
  uptime: number;
  lastSeen: string;
}

export interface Job {
  id: string;
  name: string;
  status: 'queued' | 'running' | 'succeeded' | 'failed' | 'cancelled';
  runnerId: string;
  startTime?: string;
  endTime?: string;
  duration?: number;
  logs?: string;
}

export interface Alert {
  id: string;
  level: 'info' | 'warning' | 'error' | 'critical';
  message: string;
  timestamp: string;
  resolved?: boolean;
}

interface Store {
  metrics: MetricsSummary | null;
  runners: Runner[];
  jobs: Job[];
  alerts: Alert[];
  selectedRunner: Runner | null;
  selectedJob: Job | null;
  isLoading: boolean;
  error: string | null;
  isSocketConnected: boolean;
  
  setMetrics: (metrics: MetricsSummary) => void;
  setRunners: (runners: Runner[]) => void;
  setJobs: (jobs: Job[]) => void;
  addAlert: (alert: Alert) => void;
  clearAlerts: () => void;
  setSelectedRunner: (runner: Runner | null) => void;
  setSelectedJob: (job: Job | null) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  setSocketConnected: (connected: boolean) => void;
}

export const useStore = create<Store>((set) => ({
  metrics: null,
  runners: [],
  jobs: [],
  alerts: [],
  selectedRunner: null,
  selectedJob: null,
  isLoading: false,
  error: null,
  isSocketConnected: false,
  
  setMetrics: (metrics) => set({ metrics }),
  setRunners: (runners) => set({ runners }),
  setJobs: (jobs) => set({ jobs }),
  addAlert: (alert) => set((state) => ({ alerts: [alert, ...state.alerts].slice(0, 50) })),
  clearAlerts: () => set({ alerts: [] }),
  setSelectedRunner: (runner) => set({ selectedRunner: runner }),
  setSelectedJob: (job) => set({ selectedJob: job }),
  setLoading: (loading) => set({ isLoading: loading }),
  setError: (error) => set({ error }),
  setSocketConnected: (connected) => set({ isSocketConnected: connected }),
}));
