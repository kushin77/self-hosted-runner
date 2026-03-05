import React from 'react';
import { useStore } from '../api/store';
import { Panel } from './UI';
import { Activity, Database, Shield, Zap, Cpu } from 'lucide-react';

interface StatusIndicatorProps {
  icon: React.ReactNode;
  label: string;
  status: boolean;
  details?: string;
}

const StatusIndicator: React.FC<StatusIndicatorProps> = ({
  icon,
  label,
  status,
  details,
}) => (
  <div className="flex items-center gap-3 p-2 rounded-lg bg-zinc-800/30">
    <div className={status ? 'text-green-400' : 'text-red-400'}>{icon}</div>
    <div className="flex-1">
      <div className="text-sm font-medium text-white">{label}</div>
      {details && <div className="text-xs text-zinc-400">{details}</div>}
    </div>
    <div
      className={`w-2 h-2 rounded-full ${status ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`}
    />
  </div>
);

export const SystemStatus: React.FC = () => {
  const metrics = useStore((s) => s.metrics);

  if (!metrics) return null;

  const health = metrics.health;
  const queue = metrics.queue;
  const jobs = metrics.jobs;

  return (
    <Panel variant="dark">
      <h3 className="text-lg font-semibold text-white mb-4">System Status</h3>
      <div className="space-y-2">
        <StatusIndicator
          icon={<Shield className="w-4 h-4" />}
          label="Vault Connectivity"
          status={health.vaultConnected}
          details={health.vaultConnected ? 'Connected' : 'Disconnected'}
        />
        <StatusIndicator
          icon={<Database className="w-4 h-4" />}
          label="JobStore"
          status={health.jobstoreOperational}
          details={health.jobstoreOperational ? 'Operational' : 'Error'}
        />
        <StatusIndicator
          icon={<Zap className="w-4 h-4" />}
          label="Queue System"
          status={queue.depth < 100}
          details={`${queue.depth} jobs queued, ${queue.activeJobs} active`}
        />
        <StatusIndicator
          icon={<Activity className="w-4 h-4" />}
          label="Job Processing"
          status={jobs.processed > 0}
          details={`${jobs.succeeded}/${jobs.processed} succeeded (${jobs.successRate})`}
        />
        <StatusIndicator
          icon={<Cpu className="w-4 h-4" />}
          label="Performance"
          status={metrics.latency.lastJob_ms < 5000}
          details={`Last job: ${metrics.latency.lastJob_ms}ms`}
        />
      </div>
    </Panel>
  );
};
