import React, { useState, useEffect } from 'react';
import {
  AreaChart, Area, LineChart, Line, BarChart, Bar,
  PieChart, Pie, Cell, XAxis, YAxis, CartesianGrid,
  Tooltip, Legend, ResponsiveContainer,
} from 'recharts';
import { useStore } from '../api/store';
import { Panel, GlowDot, Pill } from '../components/UI';

export const AdvancedAnalytics: React.FC = () => {
  const metrics = useStore((s) => s.metrics);
  const [jobTrend, setJobTrend] = useState<any[]>([]);
  const [latencyTrend, setLatencyTrend] = useState<any[]>([]);

  useEffect(() => {
    if (metrics) {
      const timestamp = new Date().toLocaleTimeString();
      
      setJobTrend((prev) => [
        ...prev.slice(-19),
        {
          time: timestamp,
          succeeded: metrics.jobs.succeeded,
          failed: metrics.jobs.failed,
          total: metrics.jobs.processed,
        },
      ]);

      setLatencyTrend((prev) => [
        ...prev.slice(-19),
        {
          time: timestamp,
          p50: metrics.latency.job_p50_ms,
          p95: metrics.latency.job_p95_ms,
          p99: metrics.latency.job_p99_ms,
        },
      ]);
    }
  }, [metrics?.jobs.processed]);

  if (!metrics) return <div className="text-zinc-400">Loading analytics...</div>;

  const successRate = parseFloat(metrics.jobs.successRate as string) || 0;
  const failureRate = 100 - successRate;

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Job Success Rate Pie Chart */}
        <Panel variant="dark">
          <div className="space-y-4">
            <h3 className="text-lg font-semibold text-white">Job Success Rate</h3>
            <ResponsiveContainer width="100%" height={250}>
              <PieChart>
                <Pie
                  data={[
                    { name: 'Succeeded', value: successRate },
                    { name: 'Failed', value: failureRate },
                  ]}
                  cx="50%"
                  cy="50%"
                  labelLine={false}
                  label={({ name, value }) => `${name}: ${value.toFixed(1)}%`}
                  outerRadius={80}
                  fill="#8884d8"
                  dataKey="value"
                >
                  <Cell fill="#10b981" />
                  <Cell fill="#ef4444" />
                </Pie>
                <Tooltip formatter={(value) => `${value.toFixed(1)}%`} />
              </PieChart>
            </ResponsiveContainer>
          </div>
        </Panel>

        {/* Queue Status */}
        <Panel variant="dark">
          <div className="space-y-4">
            <h3 className="text-lg font-semibold text-white">Queue Status</h3>
            <div className="space-y-3">
              <div>
                <div className="flex justify-between mb-2">
                  <span className="text-zinc-300">Queued Jobs</span>
                  <Pill variant="warning">{metrics.queue.depth}</Pill>
                </div>
                <div className="w-full bg-zinc-700 rounded-full h-2">
                  <div
                    className="bg-yellow-500 h-2 rounded-full"
                    style={{ width: `${Math.min(metrics.queue.depth / 100, 1) * 100}%` }}
                  />
                </div>
              </div>
              <div>
                <div className="flex justify-between mb-2">
                  <span className="text-zinc-300">Active Jobs</span>
                  <Pill variant="info">{metrics.queue.activeJobs}</Pill>
                </div>
              </div>
            </div>
          </div>
        </Panel>
      </div>

      {/* Job Processing Trend */}
      {jobTrend.length > 0 && (
        <Panel variant="dark">
          <div className="space-y-4">
            <h3 className="text-lg font-semibold text-white">Job Processing Trend</h3>
            <ResponsiveContainer width="100%" height={300}>
              <AreaChart data={jobTrend}>
                <defs>
                  <linearGradient id="colorSucceeded" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#10b981" stopOpacity={0.8} />
                    <stop offset="95%" stopColor="#10b981" stopOpacity={0} />
                  </linearGradient>
                  <linearGradient id="colorFailed" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#ef4444" stopOpacity={0.8} />
                    <stop offset="95%" stopColor="#ef4444" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
                <XAxis dataKey="time" stroke="#9ca3af" />
                <YAxis stroke="#9ca3af" />
                <Tooltip
                  contentStyle={{
                    backgroundColor: '#1f2937',
                    border: '1px solid #374151',
                  }}
                />
                <Area
                  type="monotone"
                  dataKey="succeeded"
                  stackId="1"
                  stroke="#10b981"
                  fillOpacity={1}
                  fill="url(#colorSucceeded)"
                />
                <Area
                  type="monotone"
                  dataKey="failed"
                  stackId="1"
                  stroke="#ef4444"
                  fillOpacity={1}
                  fill="url(#colorFailed)"
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </Panel>
      )}

      {/* Latency Percentiles */}
      {latencyTrend.length > 0 && (
        <Panel variant="dark">
          <div className="space-y-4">
            <h3 className="text-lg font-semibold text-white">Job Latency Percentiles (ms)</h3>
            <ResponsiveContainer width="100%" height={300}>
              <LineChart data={latencyTrend}>
                <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
                <XAxis dataKey="time" stroke="#9ca3af" />
                <YAxis stroke="#9ca3af" />
                <Tooltip
                  contentStyle={{
                    backgroundColor: '#1f2937',
                    border: '1px solid #374151',
                  }}
                />
                <Legend />
                <Line type="monotone" dataKey="p50" stroke="#3b82f6" name="P50" />
                <Line type="monotone" dataKey="p95" stroke="#f59e0b" name="P95" />
                <Line type="monotone" dataKey="p99" stroke="#ef4444" name="P99" />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </Panel>
      )}

      {/* Performance Metrics Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Panel variant="dark">
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-zinc-400">Terraform P50</span>
              <GlowDot color="blue" />
            </div>
            <div className="text-2xl font-bold text-white">
              {metrics.latency.terraform_p50_ms}ms
            </div>
          </div>
        </Panel>
        <Panel variant="dark">
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-zinc-400">Terraform P95</span>
              <GlowDot color="yellow" />
            </div>
            <div className="text-2xl font-bold text-white">
              {metrics.latency.terraform_p95_ms}ms
            </div>
          </div>
        </Panel>
        <Panel variant="dark">
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-zinc-400">Last Job</span>
              <GlowDot color={metrics.latency.lastJob_ms < 100 ? 'green' : 'orange'} />
            </div>
            <div className="text-2xl font-bold text-white">
              {metrics.latency.lastJob_ms}ms
            </div>
          </div>
        </Panel>
      </div>
    </div>
  );
};
