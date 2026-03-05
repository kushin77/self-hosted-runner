import React, { useState, useEffect, useRef } from 'react';
import { COLORS, rand } from '../theme';
import { Panel, PanelHeader, Pill, GlowDot } from '../components/UI';
import { AreaChart, Gauge } from '../components/Charts';

/**
 * Dashboard - Main overview page showing system metrics and status
 */
interface DashboardProps {
  tick: number;
}

export const Dashboard: React.FC<DashboardProps> = ({ tick }) => {
  const spark = useRef(Array.from({ length: 28 }, () => rand(60, 420)));
  const [runners, setRunners] = useState(482);
  const [jobsPerMin, setJobsPerMin] = useState(347);
  const [cacheHitRate, setCacheHitRate] = useState(94);
  const [aiFixedToday, setAiFixedToday] = useState(7);
  const [cpuUsage, setCpuUsage] = useState(72);
  const [memUsage, setMemUsage] = useState(68);
  const [gpuUsage, setGpuUsage] = useState(14);

  useEffect(() => {
    spark.current = [...spark.current.slice(1), rand(60, 420)];
    setRunners((v) => Math.max(400, Math.min(580, v + rand(-8, 10))));
    setJobsPerMin((v) => Math.max(200, Math.min(500, v + rand(-15, 18))));
    setCacheHitRate((v) => Math.max(70, Math.min(99, v + rand(-2, 2))));
    setAiFixedToday((v) => Math.max(0, Math.min(20, v + rand(-1, 1))));
    setCpuUsage((v) => Math.max(55, Math.min(92, v + rand(-3, 4))));
    setMemUsage((v) => Math.max(50, Math.min(88, v + rand(-2, 3))));
    setGpuUsage((v) => Math.max(8, Math.min(30, v + rand(-2, 3))));
  }, [tick]);

  

  return (
    <div
      style={{
        flex: 1,
        padding: 16,
        overflowY: 'auto',
        display: 'flex',
        flexDirection: 'column',
        gap: 10,
      }}
    >
      {/* Deployment Modes */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
        {[
          { icon: '☁️', mode: 'Managed', runners: 124, color: COLORS.accent, cost: '$0.0018/min' },
          { icon: '🏗', mode: 'BYOC — acme-aws', runners: 310, color: COLORS.cyan, cost: 'Your cloud bill' },
          { icon: '🖧', mode: 'On-Prem — nyc-dc', runners: 48, color: COLORS.purple, cost: '$0 compute' },
        ].map((m) => (
          <Panel key={m.mode} glowColor={m.color} style={{ padding: '12px 14px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
              <span style={{ fontSize: 18 }}>{m.icon}</span>
              <div>
                <div style={{ fontSize: 11, fontWeight: 700, color: m.color }}>{m.mode}</div>
                <div style={{ fontSize: 9, color: COLORS.muted }}>{m.cost}</div>
              </div>
              <Pill color="green" sm>
                LIVE
              </Pill>
            </div>
            <div style={{ fontSize: 20, fontWeight: 800, color: COLORS.text }}>
              {m.runners}{' '}
              <span style={{ fontSize: 10, color: COLORS.muted, fontWeight: 400 }}>
                runners
              </span>
            </div>
          </Panel>
        ))}
      </div>

      {/* Key Performance Indicators */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {[
          { label: 'Active Runners', val: runners, color: COLORS.accent },
          { label: 'Jobs / Min', val: jobsPerMin, color: COLORS.cyan },
          { label: 'Cache Hit Rate', val: cacheHitRate + '%', color: COLORS.green },
          { label: 'AI Fixed Today', val: aiFixedToday, color: COLORS.purple },
        ].map((s) => (
          <Panel key={s.label} style={{ padding: '10px 14px' }}>
            <div
              style={{
                fontSize: 9,
                color: COLORS.muted,
                textTransform: 'uppercase',
                letterSpacing: '0.08em',
                marginBottom: 4,
              }}
            >
              {s.label}
            </div>
            <div
              style={{
                fontSize: 22,
                fontWeight: 800,
                color: s.color,
                textShadow: `0 0 12px ${s.color}55`,
              }}
            >
              {s.val}
            </div>
          </Panel>
        ))}
      </div>

      {/* Active Agents Status */}
      <Panel glowColor={COLORS.purple}>
        <PanelHeader icon="🧠" title="Active Agents — All Runners" color={COLORS.purple} />
        <div style={{ padding: '10px 14px', display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {[
            { icon: '🔮', name: 'Failure Oracle', color: COLORS.purple },
            { icon: '⚡', name: 'Perf Profiler', color: COLORS.yellow },
            { icon: '🛡', name: 'Security Auditor', color: COLORS.red },
            { icon: '💾', name: 'Cache Oracle', color: COLORS.cyan },
          ].map((a) => (
            <div
              key={a.name}
              style={{
                background: a.color + '14',
                border: `1px solid ${a.color}33`,
                borderRadius: 7,
                padding: '7px 12px',
                display: 'flex',
                alignItems: 'center',
                gap: 7,
              }}
            >
              <GlowDot color={COLORS.green} size={6} />
              <span style={{ fontSize: 11, color: a.color, fontWeight: 700 }}>
                {a.icon} {a.name}
              </span>
              <span style={{ fontSize: 9, color: COLORS.muted }}>847+ runs</span>
            </div>
          ))}
          <div
            style={{
              background: COLORS.border + '66',
              borderRadius: 7,
              padding: '7px 12px',
              display: 'flex',
              alignItems: 'center',
              gap: 7,
            }}
          >
            <GlowDot color={COLORS.muted} size={6} />
            <span style={{ fontSize: 11, color: COLORS.muted }}>2 agents idle</span>
          </div>
        </div>
      </Panel>

      {/* Charts Row */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
        <Panel glowColor={COLORS.accent}>
          <PanelHeader icon="📈" title="Throughput — Jobs/Min" color={COLORS.accent} />
          <div style={{ padding: '12px 16px' }}>
            <AreaChart data={spark.current} color={COLORS.accent} width={290} height={80} />
          </div>
        </Panel>

        <Panel glowColor={COLORS.purple}>
          <PanelHeader
            icon="🔮"
            title="AI Oracle — Recent Fixes"
            color={COLORS.purple}
          />
          <div style={{ padding: '10px 14px', display: 'flex', flexDirection: 'column', gap: 6 }}>
            {[
              {
                repo: 'backend/worker',
                fix: 'Redis ECONNREFUSED — readinessProbe missing',
                conf: 94,
                status: 'auto-fixed' as const,
              },
              {
                repo: 'frontend/web',
                fix: 'Missing NODE_ENV in staging deploy',
                conf: 97,
                status: 'auto-fixed' as const,
              },
              {
                repo: 'ml/training',
                fix: 'CUDA OOM — reduce batch_size to 16',
                conf: 81,
                status: 'suggested' as const,
              },
            ].map((f, i) => (
              <div
                key={i}
                style={{
                  background: '#ffffff04',
                  borderRadius: 6,
                  padding: '7px 10px',
                  border: `1px solid ${COLORS.border}`,
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: 10, fontFamily: 'monospace', color: COLORS.textDim }}>
                    {f.repo}
                  </span>
                  <Pill color={f.status === 'auto-fixed' ? 'green' : 'yellow'} sm>
                    {f.status}
                  </Pill>
                </div>
                <div style={{ fontSize: 11, color: COLORS.text, marginTop: 2 }}>
                  {f.fix}
                </div>
                <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 2 }}>
                  confidence {f.conf}%
                </div>
              </div>
            ))}
          </div>
        </Panel>
      </div>

      {/* Resource Utilization & Cache */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
        <Panel>
          <PanelHeader icon="⚡" title="Resource Utilization" color={COLORS.yellow} />
          <div
            style={{
              padding: '16px',
              display: 'flex',
              justifyContent: 'space-around',
            }}
          >
            <Gauge
              value={cpuUsage}
              max={100}
              color={cpuUsage > 85 ? COLORS.red : COLORS.yellow}
              label="vCPU"
              sub="21.5k vCPU"
            />
            <Gauge
              value={memUsage}
              max={100}
              color={memUsage > 85 ? COLORS.red : COLORS.green}
              label="Memory"
              sub="172 GiB / 255 GiB"
            />
            <Gauge
              value={gpuUsage}
              max={100}
              color={COLORS.purple}
              label="GPUs"
              sub="9 / 64 GPUs"
            />
          </div>
        </Panel>

        <Panel>
          <PanelHeader icon="💾" title="LiveMirror Cache" color={COLORS.yellow} />
          <div style={{ padding: '10px 14px', display: 'flex', flexDirection: 'column', gap: 6 }}>
            {[
              { type: 'npm / pnpm', hit: 96, saved: '42s avg' },
              { type: 'Docker layers', hit: 89, saved: '3m 12s avg' },
              { type: 'pip / poetry', hit: 91, saved: '28s avg' },
              { type: 'Go modules', hit: 88, saved: '18s avg' },
            ].map((c) => (
              <div key={c.type} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: 10, color: COLORS.textDim, width: 110 }}>
                  {c.type}
                </span>
                <div
                  style={{
                    flex: 1,
                    height: 4,
                    background: COLORS.border,
                    borderRadius: 2,
                  }}
                >
                  <div
                    style={{
                      width: `${c.hit}%`,
                      height: '100%',
                      background: COLORS.yellow,
                      borderRadius: 2,
                      boxShadow: `0 0 6px ${COLORS.yellow}88`,
                    }}
                  />
                </div>
                <span style={{ fontSize: 10, color: COLORS.yellow, width: 28 }}>
                  {c.hit}%
                </span>
                <span style={{ fontSize: 9, color: COLORS.muted, width: 70 }}>
                  saved {c.saved}
                </span>
              </div>
            ))}
          </div>
        </Panel>
      </div>
    </div>
  );
};
