import React, { useState } from 'react';
import { COLORS } from '../theme';
import { Panel, PanelHeader, Pill } from '../components/UI';
import { BarChart } from '../components/Charts';

/**
 * Windows Runner Interface
 */
export interface WindowsRunner {
  os: 'Windows Server 2019' | 'Windows Server 2022';
  count: number;
  active: number;
  performanceScore: number;
  driverVersion: string;
  gpuSupport: boolean;
  uptime: number;
  rebootCycle: string;
}

/**
 * Windows Runners Fleet
 */
const WINDOWS_FLEET: WindowsRunner[] = [
  {
    os: 'Windows Server 2022',
    count: 24,
    active: 21,
    performanceScore: 94,
    driverVersion: '552.76 (NVIDIA)',
    gpuSupport: true,
    uptime: 128,
    rebootCycle: 'Weekly Sunday 2am UTC',
  },
  {
    os: 'Windows Server 2019',
    count: 12,
    active: 10,
    performanceScore: 87,
    driverVersion: '531.99 (NVIDIA)',
    gpuSupport: true,
    uptime: 89,
    rebootCycle: 'Bi-weekly Monday 2am UTC',
  },
];

/**
 * Build Framework Stats
 */
const BUILD_FRAMEWORKS = [
  { name: 'MSBuild', jobs: 8400, avgTime: '12m 34s', successRate: 98.2 },
  { name: '.NET Core', jobs: 6200, avgTime: '8m 45s', successRate: 99.1 },
  { name: 'NuGet', jobs: 5800, avgTime: '4m 12s', successRate: 99.7 },
  { name: 'Visual Studio', jobs: 3200, avgTime: '15m 20s', successRate: 97.8 },
];

/**
 * Windows-Specific Features
 */
const WINDOWS_FEATURES = [
  {
    name: 'GPU Acceleration',
    status: 'enabled',
    count: 'CUDA 12.3 on 18 runners',
    usagePercent: 62,
  },
  {
    name: 'GPU Acceleration',
    status: 'enabled',
    count: 'CUDA 11.8 on 12 runners',
    usagePercent: 58,
  },
  {
    name: 'Code Signing',
    status: 'enabled',
    count: 'EV Certificates (Trusted Root)',
    usagePercent: 100,
  },
  {
    name: 'Windows Sandbox',
    status: 'enabled',
    count: 'Available on Server 2022',
    usagePercent: 45,
  },
];

/**
 * Windows Runners Page
 */
export const WindowsRunners: React.FC = () => {
  const [expandedOS, setExpandedOS] = useState<string | null>(null);

  const totalRunners = WINDOWS_FLEET.reduce((sum, w) => sum + w.count, 0);
  const activeRunners = WINDOWS_FLEET.reduce((sum, w) => sum + w.active, 0);
  const avgPerformance = Math.round(
    WINDOWS_FLEET.reduce((sum, w) => sum + w.performanceScore, 0) / WINDOWS_FLEET.length
  );

  return (
    <div style={{ flex: 1, padding: 20, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* Header */}
      <div>
        <div style={{ fontSize: 18, fontWeight: 800, color: COLORS.text, marginBottom: 4 }}>
          Windows Runners
        </div>
        <div style={{ fontSize: 12, color: COLORS.muted }}>
          Enterprise .NET ecosystem · GPU acceleration · Code signing · Windows Sandbox
        </div>
      </div>

      {/* Key Metrics */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {[
          { label: 'Total Runners', val: totalRunners, color: COLORS.cyan },
          { label: 'Active', val: activeRunners, color: COLORS.green },
          { label: 'Avg Performance', val: `${avgPerformance}%`, color: COLORS.yellow },
          { label: 'GPU-Enabled', val: '30', color: COLORS.purple },
        ].map((m) => (
          <Panel key={m.label} style={{ padding: '12px 14px' }}>
            <div
              style={{
                fontSize: 9,
                color: COLORS.muted,
                textTransform: 'uppercase',
                letterSpacing: '0.08em',
                marginBottom: 4,
              }}
            >
              {m.label}
            </div>
            <div
              style={{
                fontSize: 20,
                fontWeight: 800,
                color: m.color,
                textShadow: `0 0 12px ${m.color}55`,
              }}
            >
              {m.val}
            </div>
          </Panel>
        ))}
      </div>

      {/* Fleet Status */}
      <Panel>
        <PanelHeader icon="🖥️" title="Windows Fleet" color={COLORS.blue} />
        <div style={{ padding: '8px 14px', display: 'flex', flexDirection: 'column', gap: 6 }}>
          {WINDOWS_FLEET.map((fleet) => (
            <div key={fleet.os}>
              <div
                onClick={() => setExpandedOS(expandedOS === fleet.os ? null : fleet.os)}
                style={{
                  background: expandedOS === fleet.os ? COLORS.blue + '12' : '#00000020',
                  border: expandedOS === fleet.os ? `1px solid ${COLORS.blue}` : `1px solid ${COLORS.border}`,
                  borderRadius: 6,
                  padding: '10px 12px',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 12,
                }}
              >
                <div
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: '50%',
                    background: COLORS.blue,
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    fontSize: 16,
                    fontWeight: 800,
                    color: '#fff',
                  }}
                >
                  {fleet.count}
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.text }}>
                    {fleet.os}
                  </div>
                  <div style={{ fontSize: 9, color: COLORS.muted }}>
                    {fleet.active} active · {fleet.performanceScore}% perf
                  </div>
                </div>
                <Pill
                  color={fleet.performanceScore > 90 ? 'green' : fleet.performanceScore > 80 ? 'yellow' : 'red'}
                  sm
                >
                  {fleet.performanceScore}%
                </Pill>
                <span style={{ fontSize: 12, color: COLORS.textDim }}>
                  {expandedOS === fleet.os ? '▲' : '▼'}
                </span>
              </div>

              {/* Expanded Details */}
              {expandedOS === fleet.os && (
                <div
                  style={{
                    background: '#000',
                    border: `1px solid ${COLORS.border}`,
                    borderRadius: 6,
                    padding: '12px',
                    marginTop: 4,
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 8,
                  }}
                >
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 8 }}>
                    <div>
                      <div style={{ fontSize: 9, color: COLORS.muted, marginBottom: 2 }}>
                        GPU Support
                      </div>
                      <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                        {fleet.gpuSupport ? '✓ CUDA Enabled' : 'CPU Only'}
                      </div>
                    </div>
                    <div>
                      <div style={{ fontSize: 9, color: COLORS.muted, marginBottom: 2 }}>
                        Driver Version
                      </div>
                      <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                        {fleet.driverVersion}
                      </div>
                    </div>
                    <div>
                      <div style={{ fontSize: 9, color: COLORS.muted, marginBottom: 2 }}>
                        Avg Uptime
                      </div>
                      <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                        {fleet.uptime} days
                      </div>
                    </div>
                    <div>
                      <div style={{ fontSize: 9, color: COLORS.muted, marginBottom: 2 }}>
                        Reboot Cycle
                      </div>
                      <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                        {fleet.rebootCycle}
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      </Panel>

      {/* Build Framework Performance */}
      <Panel>
        <PanelHeader icon="🏗️" title="Build Framework Performance" color={COLORS.yellow} />
        <div style={{ padding: '10px 14px' }}>
          <BarChart
            data={BUILD_FRAMEWORKS.map((f) => ({
              label: f.name,
              value: f.successRate,
              color: COLORS.green,
              maxValue: 100,
            }))}
          />
        </div>
        <div style={{ padding: '8px 14px', display: 'flex', flexDirection: 'column', gap: 4 }}>
          {BUILD_FRAMEWORKS.map((f) => (
            <div
              key={f.name}
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                padding: '6px 0',
                borderBottom: `1px solid ${COLORS.border}`,
                fontSize: 10,
              }}
            >
              <div>
                <div style={{ color: COLORS.text, fontWeight: 700 }}>{f.name}</div>
                <div style={{ color: COLORS.muted }}>
                  {f.jobs} jobs · Avg {f.avgTime}
                </div>
              </div>
              <Pill color="green" sm>
                {f.successRate}%
              </Pill>
            </div>
          ))}
        </div>
      </Panel>

      {/* Windows-Specific Features */}
      <Panel>
        <PanelHeader icon="⚙️" title="Advanced Features" color={COLORS.cyan} />
        <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {WINDOWS_FEATURES.map((feature) => (
            <div key={feature.name} style={{ display: 'flex', gap: 12 }}>
              <div style={{ flex: 1 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
                  <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.text }}>
                    {feature.name}
                  </div>
                  <Pill color="green" sm>
                    {feature.status}
                  </Pill>
                </div>
                <div style={{ fontSize: 9, color: COLORS.muted }}>{feature.count}</div>
              </div>
              <div style={{ width: 60, height: 32, display: 'flex', alignItems: 'center' }}>
                <div
                  style={{
                    height: 4,
                    background: COLORS.border,
                    borderRadius: 2,
                    overflow: 'hidden',
                    width: '100%',
                  }}
                >
                  <div
                    style={{
                      height: '100%',
                      background: COLORS.green,
                      width: `${feature.usagePercent}%`,
                      transition: 'width 0.3s ease',
                    }}
                  />
                </div>
              </div>
              <div style={{ width: 30, textAlign: 'right' }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.text }}>
                  {feature.usagePercent}%
                </div>
              </div>
            </div>
          ))}
        </div>
      </Panel>

      {/* System Requirements & Support */}
      <Panel>
        <PanelHeader icon="📋" title="Supported Environments" color={COLORS.green} />
        <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            {
              env: 'Windows Server 2022',
              frameworks: ['MSBuild', '.NET 6/7/8', 'NuGet', 'Visual Studio 2022'],
              status: 'Recommended',
            },
            {
              env: 'Windows Server 2019',
              frameworks: ['MSBuild', '.NET Framework 4.8', 'NuGet', 'Visual Studio 2019'],
              status: 'Supported',
            },
          ].map((item) => (
            <div key={item.env} style={{ borderBottom: `1px solid ${COLORS.border}`, paddingBottom: 8 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
                <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.text }}>
                  {item.env}
                </div>
                <Pill color={item.status === 'Recommended' ? 'green' : 'yellow'} sm>
                  {item.status}
                </Pill>
              </div>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {item.frameworks.map((f) => (
                  <Pill key={f} color="blue" sm>
                    {f}
                  </Pill>
                ))}
              </div>
            </div>
          ))}
        </div>
      </Panel>

      {/* Maintenance & Patching */}
      <Panel glowColor={COLORS.yellow}>
        <PanelHeader icon="🔧" title="Maintenance Windows" color={COLORS.yellow} />
        <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <div>
              <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 4 }}>
                Windows Updates
              </div>
              <div style={{ fontSize: 11, color: COLORS.text }}>
                Second Tuesday of every month, 2am UTC
              </div>
              <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 2 }}>
                Automated rollout with health checks, max 5 runners offline
              </div>
            </div>
            <div>
              <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 4 }}>
                Driver Updates
              </div>
              <div style={{ fontSize: 11, color: COLORS.text }}>
                NVIDIA driver updates: Monthly + hotfixes as needed
              </div>
              <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 2 }}>
                Tested on canary pool before production rollout
              </div>
            </div>
          </div>
          <button
            style={{
              background: COLORS.yellow,
              color: '#000',
              border: 'none',
              borderRadius: 4,
              padding: '6px 12px',
              fontSize: 11,
              fontWeight: 700,
              cursor: 'pointer',
              textTransform: 'uppercase',
              letterSpacing: '0.05em',
            }}
          >
            Configure Maintenance Policy
          </button>
        </div>
      </Panel>
    </div>
  );
};
