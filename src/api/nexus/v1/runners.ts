/**
 * EIQ Nexus v1 API - Runners (Multi-Cloud Control)
 * Implements ADR-0002: Multi-Cloud Runner Architecture
 */

export interface NexusRunner {
  id: string;
  name: string;
  provider: 'aws' | 'azure' | 'gcp' | 'bare-metal';
  region: string;
  instanceType?: string;
  status: 'online' | 'offline' | 'busy' | 'terminating';
  labels: string[];
  lastUsedAt: string;
}

export interface RunnerPool {
  poolId: string;
  region: string;
  minScale: number;
  maxScale: number;
  currentScale: number;
  desiredScale: number;
}

export const listRunners = async (): Promise<NexusRunner[]> => {
  // TODO: Implement K8s/Cloud integration per ADR-0002
  return [];
};

export const scalePool = async (poolId: string, count: number) => {
  console.log(`Scaling pool ${poolId} to ${count}`);
};
