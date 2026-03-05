import React, { useState, useEffect } from 'react';
import { useStore } from '../api/store';
import { Panel } from './UI';
import { Play, Pause, XCircle, CheckCircle, Clock } from 'lucide-react';

export const JobQueueMonitor: React.FC = () => {
  const metrics = useStore((s) => s.metrics);
  const [displayJobs, setDisplayJobs] = useState<any[]>([]);

  useEffect(() => {
    if (metrics) {
      const mockJobs = [
        {
          id: `job-${metrics.queue.activeJobs}-001`,
          name: 'terraform-apply-prod',
          status: 'running' as const,
          progress: Math.random() * 100,
          duration: Math.floor(Math.random() * 10000),
        },
        {
          id: 'job-002',
          name: 'vault-backup-sync',
          status: 'queued' as const,
          duration: 0,
        },
        {
          id: 'job-003',
          name: 'cache-cleanup',
          status: 'queued' as const,
          duration: 0,
        },
      ];
      setDisplayJobs(mockJobs);
    }
  }, [metrics]);

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'running':
        return <Play className="w-4 h-4 text-blue-400" />;
      case 'queued':
        return <Clock className="w-4 h-4 text-yellow-400" />;
      case 'succeeded':
        return <CheckCircle className="w-4 h-4 text-green-400" />;
      case 'failed':
        return <XCircle className="w-4 h-4 text-red-400" />;
      default:
        return <Pause className="w-4 h-4 text-zinc-400" />;
    }
  };

  if (!metrics) return null;

  return (
    <Panel variant="dark">
      <h3 className="text-lg font-semibold text-white mb-4">Job Queue Monitor</h3>
      <div className="space-y-3">
        {displayJobs.map((job) => (
          <div
            key={job.id}
            className="p-3 rounded-lg bg-zinc-800/50 border border-zinc-700"
          >
            <div className="flex items-start justify-between mb-2">
              <div className="flex items-center gap-2">
                {getStatusIcon(job.status)}
                <div>
                  <p className="text-sm font-medium text-white">{job.name}</p>
                  <p className="text-xs text-zinc-400">{job.id}</p>
                </div>
              </div>
              <span
                className={`text-xs px-2 py-1 rounded ${
                  job.status === 'running'
                    ? 'bg-blue-500/20 text-blue-300'
                    : job.status === 'queued'
                    ? 'bg-yellow-500/20 text-yellow-300'
                    : 'bg-zinc-700 text-zinc-300'
                }`}
              >
                {job.status}
              </span>
            </div>
            {job.status === 'running' && (
              <div className="w-full bg-zinc-700 rounded-full h-2">
                <div
                  className="bg-blue-500 h-2 rounded-full transition-all"
                  style={{ width: `${job.progress}%` }}
                />
              </div>
            )}
            {job.duration > 0 && (
              <p className="text-xs text-zinc-400 mt-2">
                Duration: {(job.duration / 1000).toFixed(2)}s
              </p>
            )}
          </div>
        ))}
        <div className="mt-4 pt-4 border-t border-zinc-700 text-xs text-zinc-400">
          Total queued: {metrics.queue.depth} | Active: {metrics.queue.activeJobs}
        </div>
      </div>
    </Panel>
  );
};
