// Shared mock data for the portal mock-server
module.exports = {
  runners: [
    { id: 'r-1', name: 'runner-1', mode: 'managed', os: 'ubuntu-latest', status: 'running', cpu: 36, mem: 64, gpu: 0, currentJob: 'build/front', pool: 'default', lastHeartbeat: Date.now() },
    { id: 'r-2', name: 'runner-2', mode: 'byoc', os: 'ubuntu-22.04', status: 'idle', cpu: 8, mem: 16, pool: 'batch', lastHeartbeat: Date.now() },
  ],

  events: [
    { time: '4s ago', type: 'blocked', severity: 'high', message: 'Blocked unknown registry download', details: 'Falco' },
    { time: '2m ago', type: 'sbom', severity: 'warn', message: 'SBOM generated for frontend', details: '847 packages' },
  ],

  billing: { monthlyJobs: 150000, avgMinutesPerJob: 8, gpuPercent: 25, estimate: 1299 },

  cache: [
    { name: 'npm', hitRate: 82, size: 450, sizeGB: '14.2GB', items: 18400 },
    { name: 'docker', hitRate: 95, size: 1200, sizeGB: '47.3GB', items: 240 },
  ],

  ai: [
    { id: 'ins-1', title: 'Flaky tests', severity: 'high', category: 'reliability', description: 'E2E flakiness', recommendation: 'Increase timeouts', impact: '~$1,200/month', implemented: true, historicalData: [22,20,18,17,18,16,14,12,11] },
  ],

  agents: [
    { id: 'oracle', icon: '🔮', name: 'Failure Oracle', color: '#8B5CF6', status: 'active', runs: 847, description: 'Streams job logs on failure', tags: ['log','fix'], config: {} },
  ],
};
