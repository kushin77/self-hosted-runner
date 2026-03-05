import { RunnerDTO, EventDTO, BillingDTO, CacheLayerDTO, AIInsightDTO } from './types';

// Minimal API client abstraction with mock responses for local dev.
// When a real backend URL is provided via VITE_API_BASE, forward calls there.

const base = (import.meta as any).env.VITE_API_BASE || '';
const useMock = !base; // mock when no backend base URL


const mockRunners: RunnerDTO[] = [
  { id: 'r-1', name: 'runner-1', mode: 'managed', os: 'ubuntu-latest', status: 'running', cpu: 36, mem: 64, gpu: 0, currentJob: 'build/front', pool: 'default', lastHeartbeat: '3s ago' },
  { id: 'r-2', name: 'runner-2', mode: 'byoc', os: 'ubuntu-22.04', status: 'idle', cpu: 8, mem: 16, pool: 'batch', lastHeartbeat: '12s ago' },
];

const mockEvents: EventDTO[] = [
  { time: '4s ago', type: 'blocked', severity: 'high', message: 'Blocked unknown registry download', details: 'Falco' },
  { time: '2m ago', type: 'sbom', severity: 'warn', message: 'SBOM generated for frontend', details: '847 packages' },
];

const mockBilling: BillingDTO = { monthlyJobs: 150000, avgMinutesPerJob: 8, gpuPercent: 25, estimate: 1299 };

const mockCache: CacheLayerDTO[] = [
  { name: 'npm', hitRate: 82, sizeGB: '14.2GB', items: 18400 },
  { name: 'docker', hitRate: 95, sizeGB: '47.3GB', items: 240 },
];

const mockAI: AIInsightDTO[] = [
  { id: 'ins-1', title: 'Flaky tests', severity: 'high', category: 'reliability', description: 'E2E flakiness', recommendation: 'Increase timeouts' },
];

async function fetchJson<T>(path: string): Promise<T> {
  if (useMock) {
    // small deterministic delay
    await new Promise((r) => setTimeout(r, 120));
    switch (path) {
      case '/api/runners':
        return (mockRunners as unknown) as T;
      case '/api/events':
        return (mockEvents as unknown) as T;
      case '/api/billing':
        return (mockBilling as unknown) as T;
      case '/api/cache':
        return (mockCache as unknown) as T;
      case '/api/ai':
        return (mockAI as unknown) as T;
      default:
        throw new Error('Unknown mock path: ' + path);
    }
  }

  const url = base + path;
  const res = await fetch(url, { headers: { 'Accept': 'application/json' } });
  if (!res.ok) throw new Error(`API error ${res.status} ${res.statusText}`);
  return (await res.json()) as T;
}

export const api = {
  getRunners: async (): Promise<RunnerDTO[]> => fetchJson<RunnerDTO[]>('/api/runners'),
  getEvents: async (): Promise<EventDTO[]> => fetchJson<EventDTO[]>('/api/events'),
  getBilling: async (): Promise<BillingDTO> => fetchJson<BillingDTO>('/api/billing'),
  getCacheLayers: async (): Promise<CacheLayerDTO[]> => fetchJson<CacheLayerDTO[]>('/api/cache'),
  getAIInsights: async (): Promise<AIInsightDTO[]> => fetchJson<AIInsightDTO[]>('/api/ai'),
};
