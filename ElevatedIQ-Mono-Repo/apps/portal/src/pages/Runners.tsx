import React, { useState, useEffect } from 'react';
import { COLORS, rand } from '../theme';
import { useTick } from '../hooks';
import { Panel, PanelHeader, Pill, ProgressBar } from '../components/UI';

/**
 * Runner Interface
 */
export interface Runner {
  id: string;
  name: string;
  mode: 'managed' | 'byoc' | 'onprem';
  os: 'linux' | 'windows' | 'macos';
  status: 'running' | 'idle' | 'provisioning' | 'draining' | 'error';
  cpu: number;
  mem: number;
  gpu?: number;
  currentJob: string | null;
  age: string;
  pool: string;
  lastHeartbeat: number;
}

/**
 * Sample Runners Data
 */
const INITIAL_RUNNERS: Runner[] = [
  {
    id: 'rc-managed-a3f9b',
    name: 'rc-managed-a3f9b',
    mode: 'managed',
    os: 'linux',
    status: 'running',
    cpu: 72,
    mem: 58,
    currentJob: 'frontend/web · build',
    age: '4m 12s',
    pool: 'spot',
    lastHeartbeat: Date.now(),
  },
  {
    id: 'rc-byoc-c1d4e',
    name: 'rc-byoc-c1d4e',
    mode: 'byoc',
    os: 'linux',
    status: 'running',
    cpu: 45,
    mem: 33,
    currentJob: 'backend/api · deploy',
    age: '1m 48s',
    pool: 'on-demand',
    lastHeartbeat: Date.now(),
  },
  {
    id: 'rc-byoc-b7f2a',
    name: 'rc-byoc-b7f2a',
    mode: 'byoc',
    os: 'linux',
    status: 'running',
    cpu: 88,
    mem: 91,
    currentJob: 'frontend/web · lint',
    age: '7m 03s',
    pool: 'spot',
    lastHeartbeat: Date.now(),
  },
  {
    id: 'rc-windows-f5a1b',
    name: 'rc-windows-f5a1b',
    mode: 'managed',
    os: 'windows',
    status: 'running',
    cpu: 61,
    mem: 44,
    currentJob: 'unity-game · il2cpp-build',
    age: '12m 30s',
    pool: 'windows-2025-4x',
    lastHeartbeat: Date.now(),
  },
  {
    id: 'rc-onprem-e9c3d',
    name: 'rc-onprem-e9c3d',
    mode: 'onprem',
    os: 'linux',
    status: 'idle',
    cpu: 2,
    mem: 8,
    currentJob: null,
    age: '22s',
    pool: 'datacenter-nyc',
    lastHeartbeat: Date.now(),
  },
  {
    id: 'rc-byoc-gpu-d8',
    name: 'rc-byoc-gpu-d8',
    mode: 'byoc',
    os: 'linux',
    status: 'running',
    cpu: 34,
    mem: 52,
    gpu: 80,
    currentJob: 'ml/training · finetune',
    age: '2m 30s',
    pool: 'gpu-g6e',
    lastHeartbeat: Date.now(),
  },
  {
    id: 'rc-managed-provisioning',
    name: 'rc-managed-provisioning',
    mode: 'managed',
    os: 'linux',
    status: 'provisioning',
    cpu: 0,
    mem: 0,
    currentJob: null,
    age: '3s',
    pool: 'spot',
    lastHeartbeat: Date.now(),
  },
  {
    id: 'rc-byoc-draining',
    name: 'rc-byoc-draining',
    mode: 'byoc',
    os: 'linux',
    status: 'draining',
    cpu: 12,
    mem: 18,
    currentJob: null,
    age: '45m 22s',
    pool: 'on-demand',
    lastHeartbeat: Date.now(),
  },
];

/**
 * Runner Row Component
 */
interface RunnerRowProps {
  runner: Runner;
}

const RunnerRow: React.FC<RunnerRowProps> = ({ runner }) => {
  const modeColorMap = {
    managed: COLORS.accent,
    byoc: COLORS.cyan,
    onprem: COLORS.purple,
  };

  const statusColorMap = {
    running: 'green',
    idle: 'gray',
    provisioning: 'yellow',
    draining: 'red',
    error: 'red',
  };

  const osIcon = {
    linux: '🐧',
    windows: '🪟',
    macos: '🍎',
  };

  return (
    <tr style={{ borderBottom: `1px solid ${COLORS.border}` }}>
      <td
        style={{
          padding: '9px 12px',
          fontFamily: 'monospace',
          fontSize: 11,
          color: COLORS.text,
        }}
      >
        {runner.name}
      </td>
      <td style={{ padding: '9px 12px' }}>
        <Pill
          color={
            runner.mode === 'managed' ? 'blue' : runner.mode === 'byoc' ? 'cyan' : 'purple'
          }
          sm
        >
          {runner.mode}
        </Pill>
      </td>
      <td style={{ padding: '9px 12px', fontSize: 14, textAlign: 'center' }}>
        {osIcon[runner.os]}
      </td>
      <td style={{ padding: '9px 12px' }}>
        <Pill color={statusColorMap[runner.status]} sm>
          {runner.status}
        </Pill>
      </td>
      <td style={{ padding: '9px 12px' }}>
        <ProgressBar value={runner.cpu} max={100} />
      </td>
      <td style={{ padding: '9px 12px' }}>
        <ProgressBar value={runner.mem} max={100} />
      </td>
      {runner.gpu !== undefined && (
        <td style={{ padding: '9px 12px' }}>
          <ProgressBar value={runner.gpu} max={100} color={COLORS.purple} />
        </td>
      )}
      <td
        style={{
          padding: '9px 12px',
          fontSize: 10,
          color: COLORS.textDim,
          maxWidth: 200,
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          whiteSpace: 'nowrap',
        }}
      >
        {runner.currentJob || '—'}
      </td>
      <td style={{ padding: '9px 12px', fontSize: 10, color: COLORS.muted }}>
        {runner.age}
      </td>
    </tr>
  );
};

/**
 * Runners Page
 */
export const Runners: React.FC = () => {
  const tick = useTick(2500);
  const [runners, setRunners] = useState<Runner[]>(INITIAL_RUNNERS);
  const [filter, setFilter] = useState<'all' | 'running' | 'idle' | 'managed' | 'byoc'>(
    'all'
  );

  // Update runner metrics on tick
  useEffect(() => {
    setRunners((rs) =>
      rs.map((r) => {
        if (r.status === 'running') {
          return {
            ...r,
            cpu: Math.min(98, Math.max(5, r.cpu + rand(-5, 7))),
            mem: Math.min(98, Math.max(5, r.mem + rand(-3, 5))),
            gpu: r.gpu ? Math.min(98, Math.max(5, r.gpu + rand(-4, 6))) : undefined,
          };
        }
        return r;
      })
    );
  }, [tick]);

  // Filter runners
  const filteredRunners = runners.filter((r) => {
    if (filter === 'all') return true;
    if (filter === 'running') return r.status === 'running';
    if (filter === 'idle') return r.status === 'idle';
    if (filter === 'managed') return r.mode === 'managed';
    if (filter === 'byoc') return r.mode === 'byoc';
    return true;
  });

  const runningCount = runners.filter((r) => r.status === 'running').length;
  const idleCount = runners.filter((r) => r.status === 'idle').length;

  return (
    <div style={{ flex: 1, padding: 20, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* Summary Stats */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {[
          { label: 'Total Runners', val: runners.length, color: COLORS.accent },
          { label: 'Running', val: runningCount, color: COLORS.green },
          { label: 'Idle', val: idleCount, color: COLORS.muted },
          { label: 'Provisioning', val: runners.filter((r) => r.status === 'provisioning').length, color: COLORS.yellow },
        ].map((s) => (
          <Panel key={s.label} style={{ padding: '12px 14px' }}>
            <div style={{ fontSize: 10, color: COLORS.muted, textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 4 }}>
              {s.label}
            </div>
            <div style={{ fontSize: 22, fontWeight: 800, color: s.color, textShadow: `0 0 12px ${s.color}55` }}>
              {s.val}
            </div>
          </Panel>
        ))}
      </div>

      {/* Header & Filters */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
        }}
      >
        <div>
          <div style={{ fontSize: 18, fontWeight: 700, color: COLORS.text }}>All Runners</div>
          <div style={{ fontSize: 12, color: COLORS.muted, marginTop: 2 }}>
            Ephemeral pods · JIT tokens · live metrics
          </div>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          {['all', 'running', 'idle', 'managed', 'byoc'].map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f as any)}
              style={{
                background: filter === f ? COLORS.accent + '22' : COLORS.border,
                border: filter === f ? `1px solid ${COLORS.accent}` : '1px solid transparent',
                color: filter === f ? COLORS.accent : COLORS.textDim,
                borderRadius: 4,
                padding: '4px 12px',
                fontSize: 11,
                cursor: 'pointer',
                fontWeight: filter === f ? 700 : 400,
                textTransform: 'capitalize',
              }}
            >
              {f}
            </button>
          ))}
        </div>
      </div>

      {/* Runners Table */}
      <Panel>
        <table
          style={{
            width: '100%',
            borderCollapse: 'collapse',
            tableLayout: 'fixed',
          }}
        >
          <thead>
            <tr style={{ borderBottom: `1px solid ${COLORS.border}`, background: COLORS.bg }}>
              {[
                'Pod Name',
                'Mode',
                'OS',
                'Status',
                'CPU',
                'Memory',
                ...(runners.some((r) => r.gpu !== undefined) ? ['GPU'] : []),
                'Current Job',
                'Age',
              ].map((h, i) => (
                <th
                  key={h}
                  style={{
                    padding: '8px 12px',
                    textAlign: 'left',
                    fontSize: 9,
                    color: COLORS.muted,
                    textTransform: 'uppercase',
                    letterSpacing: '0.06em',
                    fontWeight: 600,
                    width: h === 'Pod Name' ? '15%' : h === 'Current Job' ? '30%' : 'auto',
                  }}
                >
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {filteredRunners.map((r) => (
              <RunnerRow key={r.id} runner={r} />
            ))}
          </tbody>
        </table>
      </Panel>

      {filteredRunners.length === 0 && (
        <div
          style={{
            textAlign: 'center',
            padding: 40,
            color: COLORS.muted,
          }}
        >
          <div style={{ fontSize: 14 }}>No runners found</div>
          <div style={{ fontSize: 12, marginTop: 4 }}>
            Try adjusting your filters
          </div>
        </div>
      )}
    </div>
  );
};
