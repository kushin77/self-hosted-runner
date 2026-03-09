import React, { useEffect, useState } from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

interface Credential {
  id: string;
  type: string;
  name: string;
  created_at: string;
  updated_at: string;
}

interface AuditEntry {
  timestamp: string;
  method: string;
  path: string;
  userAgent: string;
  userId: string;
}

interface MetricData {
  timestamp: string;
  uptime: number;
  memoryUsage: number;
}

const Dashboard: React.FC = () => {
  const [credentials, setCredentials] = useState<Credential[]>([]);
  const [auditTrail, setAuditTrail] = useState<AuditEntry[]>([]);
  const [metrics, setMetrics] = useState<MetricData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:3000';

  // Fetch credentials
  useEffect(() => {
    const fetchCredentials = async () => {
      try {
        const response = await fetch(`${API_BASE}/credentials`);
        if (!response.ok) throw new Error('Failed to fetch credentials');
        const data = await response.json();
        setCredentials(data.credentials || []);
      } catch (err: any) {
        setError(err.message);
      }
    };

    fetchCredentials();
    // Refresh every 30 seconds
    const interval = setInterval(fetchCredentials, 30000);
    return () => clearInterval(interval);
  }, []);

  // Fetch audit trail
  useEffect(() => {
    const fetchAudit = async () => {
      try {
        const response = await fetch(`${API_BASE}/audit?limit=50`);
        if (!response.ok) throw new Error('Failed to fetch audit trail');
        const data = await response.json();
        setAuditTrail(data.entries || []);
      } catch (err: any) {
        setError(err.message);
      }
    };

    fetchAudit();
    // Refresh every 60 seconds
    const interval = setInterval(fetchAudit, 60000);
    return () => clearInterval(interval);
  }, []);

  // Fetch metrics
  useEffect(() => {
    const fetchMetrics = async () => {
      try {
        const response = await fetch(`${API_BASE}/metrics`);
        if (!response.ok) throw new Error('Failed to fetch metrics');
        
        // Parse Prometheus metrics and convert to chart data
        const text = await response.text();
        const uptime = text.match(/nexus_portal_uptime_seconds\s([\d.]+)/)?.[1] || '0';
        
        setMetrics((prev) => [
          ...prev.slice(-59), // Keep last 60 points
          {
            timestamp: new Date().toLocaleTimeString(),
            uptime: parseFloat(uptime),
            memoryUsage: process.memoryUsage().heapUsed / 1024 / 1024, // MB
          },
        ]);
      } catch (err: any) {
        setError(err.message);
      } finally {
        setLoading(false);
      }
    };

    fetchMetrics();
    // Refresh every 10 seconds
    const interval = setInterval(fetchMetrics, 10000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="min-h-screen bg-gray-900 text-white p-8">
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-4xl font-bold mb-2">🛡️ NexusShield Portal</h1>
        <p className="text-gray-400">Enterprise Credential Management &amp; Orchestration</p>
      </div>

      {/* Error Banner */}
      {error && (
        <div className="mb-8 bg-red-900 border border-red-700 rounded p-4">
          <p className="text-red-200">⚠️ Error: {error}</p>
        </div>
      )}

      {/* Stats Grid */}
      <div className="grid grid-cols-4 gap-4 mb-8">
        <div className="bg-gray-800 rounded-lg p-6">
          <p className="text-gray-400 text-sm">Total Credentials</p>
          <p className="text-3xl font-bold">{credentials.length}</p>
        </div>
        <div className="bg-gray-800 rounded-lg p-6">
          <p className="text-gray-400 text-sm">Recent Audit Entries</p>
          <p className="text-3xl font-bold">{auditTrail.length}</p>
        </div>
        <div className="bg-gray-800 rounded-lg p-6">
          <p className="text-gray-400 text-sm">API Status</p>
          <p className="text-3xl font-bold text-green-400">✅ Healthy</p>
        </div>
        <div className="bg-gray-800 rounded-lg p-6">
          <p className="text-gray-400 text-sm">Data Points</p>
          <p className="text-3xl font-bold">{metrics.length}</p>
        </div>
      </div>

      {/* Metrics Chart */}
      <div className="bg-gray-800 rounded-lg p-6 mb-8">
        <h2 className="text-xl font-bold mb-4">📊 System Metrics (Last 60 seconds)</h2>
        {metrics.length > 0 ? (
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={metrics}>
              <CartesianGrid strokeDasharray="3 3" stroke="#444" />
              <XAxis dataKey="timestamp" stroke="#888" />
              <YAxis stroke="#888" />
              <Tooltip contentStyle={{ backgroundColor: '#1f2937', border: '1px solid #444' }} />
              <Legend />
              <Line 
                type="monotone" 
                dataKey="uptime" 
                stroke="#10b981" 
                strokeWidth={2}
                name="Uptime (seconds)"
              />
              <Line 
                type="monotone" 
                dataKey="memoryUsage" 
                stroke="#3b82f6" 
                strokeWidth={2}
                name="Memory Usage (MB)"
              />
            </LineChart>
          </ResponsiveContainer>
        ) : (
          <p className="text-gray-500">Loading metrics...</p>
        )}
      </div>

      {/* Credentials Table */}
      <div className="bg-gray-800 rounded-lg p-6 mb-8">
        <h2 className="text-xl font-bold mb-4">🔐 Credentials ({credentials.length})</h2>
        {credentials.length > 0 ? (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-700">
                  <th className="text-left py-3 px-4">Type</th>
                  <th className="text-left py-3 px-4">Name</th>
                  <th className="text-left py-3 px-4">Created</th>
                  <th className="text-left py-3 px-4">Updated</th>
                </tr>
              </thead>
              <tbody>
                {credentials.slice(0, 10).map((cred) => (
                  <tr key={cred.id} className="border-b border-gray-700 hover:bg-gray-700 transition">
                    <td className="py-3 px-4">
                      <span className="bg-blue-900 text-blue-200 px-2 py-1 rounded text-xs">
                        {cred.type.toUpperCase()}
                      </span>
                    </td>
                    <td className="py-3 px-4 font-mono text-gray-300">{cred.name}</td>
                    <td className="py-3 px-4 text-gray-500 text-xs">
                      {new Date(cred.created_at).toLocaleDateString()}
                    </td>
                    <td className="py-3 px-4 text-gray-500 text-xs">
                      {new Date(cred.updated_at).toLocaleDateString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-gray-500">{loading ? 'Loading credentials...' : 'No credentials found'}</p>
        )}
      </div>

      {/* Audit Trail */}
      <div className="bg-gray-800 rounded-lg p-6">
        <h2 className="text-xl font-bold mb-4">📋 Audit Trail (Last 50 entries)</h2>
        {auditTrail.length > 0 ? (
          <div className="space-y-2 max-h-96 overflow-y-auto">
            {auditTrail.slice(-10).reverse().map((entry, idx) => (
              <div key={idx} className="bg-gray-900 p-3 rounded text-xs font-mono text-gray-400">
                <div className="flex justify-between">
                  <span className="text-gray-300">{entry.method}</span>
                  <span>{entry.path}</span>
                  <span className="text-gray-500">{new Date(entry.timestamp).toLocaleTimeString()}</span>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-gray-500">{loading ? 'Loading audit trail...' : 'No audit entries found'}</p>
        )}
      </div>

      {/* Footer */}
      <div className="mt-8 border-t border-gray-700 pt-4 text-center text-gray-500 text-xs">
        <p>
          NexusShield Portal MVP v1.0.0-alpha | Last updated: {new Date().toLocaleString()}
        </p>
      </div>
    </div>
  );
};

export default Dashboard;
