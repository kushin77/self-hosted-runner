// Shared mock data for the portal mock-server
const { v4: uuidv4 } = require('uuid');

// Runner list
const runners = [
  { id: 'r-1', name: 'runner-1', mode: 'managed', os: 'linux', status: 'busy', labels: ['docker','node'], arch: 'x64', uptime: 3600 * 5, jobsCompleted: 124, lastJobTime: Date.now() - 300000, createdAt: Date.now() - 86400000 },
  { id: 'r-2', name: 'runner-2', mode: 'byoc', os: 'linux', status: 'idle', labels: ['ci'], arch: 'x64', uptime: 3600 * 24, jobsCompleted: 42, lastJobTime: Date.now() - 7200000, createdAt: Date.now() - 604800000 },
];

// Event type helpers - more closely aligned with Falco/Tetragon-like payloads
const EVENT_TYPES = ['runner_created','runner_failed','job_started','job_completed','job_failed','scaling_event'];
const SEVERITIES = ['info','warning','error'];

function randomChoice(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

function generateEvent() {
  const type = randomChoice(EVENT_TYPES);
  const severity = type === 'job_failed' || type === 'runner_failed' ? 'error' : type === 'scaling_event' ? 'warning' : 'info';
  const runner = randomChoice(runners);
  const jobId = `job-${Math.floor(Math.random() * 100000)}`;
  const base = {
    id: uuidv4(),
    type,
    timestamp: Date.now(),
    runnerId: runner.id,
    jobId: type.startsWith('job_') ? jobId : undefined,
    message: `${type} detected on ${runner.name}`,
    severity,
    metadata: {
      container: `ctr_${Math.random().toString(36).slice(2,8)}`,
      syscall: randomChoice(['open','connect','execve','unlink','read']),
      process: randomChoice(['docker','git','npm','python','bash']),
      pid: Math.floor(Math.random() * 32000),
    },
  };
  return base;
}

// Seed a handful of recent events
const events = [];
for (let i = 0; i < 12; i++) {
  const e = generateEvent();
  // spread timestamps backwards
  e.timestamp = Date.now() - (12 - i) * 1000 * 15;
  events.push(e);
}

const billing = { currentMonth: { runnerMinutes: 50000, cacheHits: 12000, estimatedCost: 1299 }, history: [], currency: 'USD' };

const cache = [
  { name: 'npm', hitRate: 82, size: 450 * 1024 * 1024, items: 18400 },
  { name: 'docker', hitRate: 95, size: 1200 * 1024 * 1024, items: 240 },
];

const ai = [
  { id: 'ins-1', title: 'Flaky tests', severity: 'high', category: 'reliability', description: 'E2E flakiness observed in last 7 days', recommendation: 'Increase timeouts and parallelize', impact: '~$1,200/month', implemented: true, historicalData: [22,20,18,17,18,16,14,12,11] },
];

const agents = [
  { id: 'oracle', icon: '🔮', name: 'Failure Oracle', color: '#8B5CF6', status: 'active', runs: 847, description: 'Streams job logs on failure', tags: ['log','fix'], config: {} },
];

module.exports = {
  runners,
  events,
  billing,
  cache,
  ai,
  agents,
  generateEvent,
};
