import React, { Suspense, lazy } from 'react';
import { AlertsPanel } from '../components/Alerts';
import { SystemStatus } from '../components/SystemStatus';

const AdvancedAnalytics = lazy(() =>
  import('./Analytics').then((m) => ({ default: m.AdvancedAnalytics }))
);

export const Observability: React.FC = () => {
  return (
    <div className="space-y-6 p-6">
      <div className="space-y-2">
        <h1 className="text-3xl font-bold text-white">Observability & Monitoring</h1>
        <p className="text-zinc-400">
          Real-time system metrics, performance analytics, and health monitoring
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2">
          <Suspense fallback={<div className="text-zinc-400">Loading analytics...</div>}>
            <AdvancedAnalytics />
          </Suspense>
        </div>
        <div className="space-y-6">
          <SystemStatus />
          <AlertsPanel />
        </div>
      </div>
    </div>
  );
};
