import React from 'react';
import { useStore } from '../api/store';
import { Panel } from './UI';
import { AlertCircle, CheckCircle, AlertTriangle, Zap } from 'lucide-react';

export const AlertsPanel: React.FC = () => {
  const alerts = useStore((s) => s.alerts);
  const clearAlerts = useStore((s) => s.clearAlerts);

  const getIcon = (level: string) => {
    switch (level) {
      case 'error':
      case 'critical':
        return <AlertCircle className="w-4 h-4 text-red-500" />;
      case 'warning':
        return <AlertTriangle className="w-4 h-4 text-yellow-500" />;
      case 'info':
        return <Zap className="w-4 h-4 text-blue-500" />;
      default:
        return <CheckCircle className="w-4 h-4 text-green-500" />;
    }
  };

  const getColor = (level: string) => {
    switch (level) {
      case 'error':
      case 'critical':
        return 'text-red-400';
      case 'warning':
        return 'text-yellow-400';
      case 'info':
        return 'text-blue-400';
      default:
        return 'text-green-400';
    }
  };

  const recentAlerts = alerts.slice(0, 5);

  return (
    <Panel variant="dark">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-white">Alerts & Notifications</h3>
        {alerts.length > 0 && (
          <button
            onClick={clearAlerts}
            className="text-xs text-zinc-400 hover:text-zinc-200"
          >
            Clear All
          </button>
        )}
      </div>

      {recentAlerts.length === 0 ? (
        <div className="text-center py-8">
          <div className="text-zinc-500 text-sm">All systems nominal</div>
        </div>
      ) : (
        <div className="space-y-3">
          {recentAlerts.map((alert) => (
            <div
              key={alert.id}
              className="flex items-start gap-3 p-3 rounded-lg bg-zinc-800/50 border border-zinc-700"
            >
              <div className="mt-1">{getIcon(alert.level)}</div>
              <div className="flex-1">
                <p className={`text-sm font-medium ${getColor(alert.level)}`}>
                  {alert.message}
                </p>
                <p className="text-xs text-zinc-500 mt-1">
                  {new Date(alert.timestamp).toLocaleTimeString()}
                </p>
              </div>
            </div>
          ))}
        </div>
      )}
    </Panel>
  );
};
