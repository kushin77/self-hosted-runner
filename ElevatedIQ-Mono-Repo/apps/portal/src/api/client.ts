import { useEffect, useState } from 'react';
import { useStore, MetricsSummary, Alert } from './store';

const API_BASE = 'http://localhost:9090';

export interface FetchOptions {
  interval?: number;
  onError?: (error: string) => void;
}

export const useMetrics = (options: FetchOptions = {}) => {
  const { interval = 5000 } = options;
  const { setMetrics, setLoading, setError, addAlert, isSocketConnected } = useStore();
  const [isConnected, setIsConnected] = useState(false);

  useEffect(() => {
    let intervalId: NodeJS.Timeout;
    let isMounted = true;

    const fetchMetrics = async () => {
      try {
        setLoading(true);
        const response = await fetch(`${API_BASE}/metrics/summary`);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data: MetricsSummary = await response.json();
        
        if (isMounted) {
          setMetrics(data);
          setError(null);
          setIsConnected(true);

          // Detect unhealthy conditions
          if (!data.health.vaultConnected) {
            addAlert({
              id: `vault-${Date.now()}`,
              level: 'error',
              message: 'Vault connectivity lost',
              timestamp: new Date().toISOString(),
            });
          }
          if (!data.health.jobstoreOperational) {
            addAlert({
              id: `jobstore-${Date.now()}`,
              level: 'error',
              message: 'JobStore operational error',
              timestamp: new Date().toISOString(),
            });
          }
          if (data.queue.depth > 100) {
            addAlert({
              id: `queue-${Date.now()}`,
              level: 'warning',
              message: `Queue depth high: ${data.queue.depth} jobs queued`,
              timestamp: new Date().toISOString(),
            });
          }
        }
      } catch (error) {
        if (isMounted) {
          const msg = error instanceof Error ? error.message : 'Failed to fetch metrics';
          setError(msg);
          setIsConnected(false);
          options.onError?.(msg);
        }
      } finally {
        if (isMounted) setLoading(false);
      }
    };

    // If a socket connection is active we rely on real-time updates
    if (!isSocketConnected) {
      fetchMetrics();
      intervalId = setInterval(fetchMetrics, interval);
    } else {
      // mark connected when socket is active and we already have data
      setIsConnected(true);
    }

    return () => {
      isMounted = false;
      clearInterval(intervalId);
    };
  }, [interval, setMetrics, setLoading, setError, addAlert, options, isSocketConnected]);

  return { isConnected };
};

export const apiClient = {
  async getMetrics(): Promise<MetricsSummary> {
    const response = await fetch(`${API_BASE}/metrics/summary`);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  },

  async getHealth() {
    const response = await fetch(`${API_BASE}/health`);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  },

  async getReadiness() {
    const response = await fetch(`${API_BASE}/ready`);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  },
};
