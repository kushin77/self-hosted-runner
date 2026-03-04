import React, { useState, useEffect } from 'react';
import { COLORS } from '../theme';
import { Panel, PanelHeader, Pill } from '../components/UI';
import { BarChart } from '../components/Charts';
import { api } from '../api';

/**
 * Billing & TCO Calculator Page
 */
export const Billing: React.FC = () => {
  const [monthlyJobs, setMonthlyJobs] = useState(150000);
  const [avgMinutesPerJob, setAvgMinutesPerJob] = useState(8);
  const [gpuPercent, setGpuPercent] = useState(25);

  useEffect(() => {
    let mounted = true;
    api
      .getBilling()
      .then((b: any) => {
        if (!mounted || !b) return;
        if (typeof b.monthlyJobs === 'number') setMonthlyJobs(b.monthlyJobs);
        if (typeof b.avgMinutesPerJob === 'number') setAvgMinutesPerJob(b.avgMinutesPerJob);
        if (typeof b.gpuPercent === 'number') setGpuPercent(b.gpuPercent);
      })
      .catch(() => {});

    return () => { mounted = false; };
  }, []);

  // Calculations
  const totalJobMinutes = monthlyJobs * avgMinutesPerJob;
  const gpuMinutes = totalJobMinutes * (gpuPercent / 100);
  const cpuMinutes = totalJobMinutes - gpuMinutes;

  // Pricing (monthly)
  const githubActions = totalJobMinutes / 60 * 0.008; // $0.008 per minute
  const runnerCosts = (totalJobMinutes / 60 / 2000) * 1200; // ~1.2k/month per runner + depreciation
  const infraCosts = 800; // Network, storage, observability

  const elevatediqCost = totalJobMinutes < 500000
    ? 499 // Starter
    : totalJobMinutes < 2000000
    ? 1299 // Professional
    : 2999; // Enterprise

  // Competitor estimates
  const circleci = totalJobMinutes * 0.00012; // Approx
  const orbCI = totalJobMinutes * 0.0001; // Approx
  const buildkite = totalJobMinutes * 0.000085; // Approx

  const totalGHA = githubActions + runnerCosts + infraCosts;

  const savings = totalGHA - elevatediqCost;
  const savingsPercent = Math.round((savings / totalGHA) * 100);

  console.log('Billing Calc:', { totalJobMinutes, gpuMinutes, cpuMinutes, githubActions, runnerCosts, infraCosts, totalGHA, elevatediqCost, savings });

  return (
    <div style={{ flex: 1, padding: 20, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* Header */}
      <div>
        <div style={{ fontSize: 18, fontWeight: 800, color: COLORS.text, marginBottom: 4 }}>
          Billing & TCO Calculator
        </div>
        <div style={{ fontSize: 12, color: COLORS.muted }}>
          Monthly cost comparison · GitHub Actions vs Self-hosted vs RunnerCloud
        </div>
      </div>

      {/* Input Controls */}
      <Panel>
        <PanelHeader icon="⚙" title="Usage Parameters" color={COLORS.accent} />
        <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 14 }}>
          {/* Monthly Jobs Slider */}
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6, alignItems: 'baseline' }}>
              <label style={{ fontSize: 11, color: COLORS.textDim, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                Monthly Jobs
              </label>
              <span
                style={{
                  fontSize: 14,
                  fontWeight: 700,
                  color: COLORS.accent,
                }}
              >
                {monthlyJobs.toLocaleString()}
              </span>
            </div>
            <input
              type="range"
              min="10000"
              max="1000000"
              step="10000"
              value={monthlyJobs}
              onChange={(e) => setMonthlyJobs(parseInt(e.target.value))}
              style={{
                width: '100%',
                height: 4,
                borderRadius: 2,
                background: COLORS.border,
                outline: 'none',
                cursor: 'pointer',
                accentColor: COLORS.accent,
              }}
            />
            <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 4 }}>
              10k — 1M jobs/month
            </div>
          </div>

          {/* Average Minutes Per Job */}
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6, alignItems: 'baseline' }}>
              <label style={{ fontSize: 11, color: COLORS.textDim, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                Avg Minutes/Job
              </label>
              <span
                style={{
                  fontSize: 14,
                  fontWeight: 700,
                  color: COLORS.cyan,
                }}
              >
                {avgMinutesPerJob}m
              </span>
            </div>
            <input
              type="range"
              min="1"
              max="30"
              step="1"
              value={avgMinutesPerJob}
              onChange={(e) => setAvgMinutesPerJob(parseInt(e.target.value))}
              style={{
                width: '100%',
                height: 4,
                borderRadius: 2,
                background: COLORS.border,
                outline: 'none',
                cursor: 'pointer',
                accentColor: COLORS.cyan,
              }}
            />
            <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 4 }}>
              1 — 30 minutes
            </div>
          </div>

          {/* GPU Job Percent */}
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6, alignItems: 'baseline' }}>
              <label style={{ fontSize: 11, color: COLORS.textDim, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                GPU Jobs (%)
              </label>
              <span
                style={{
                  fontSize: 14,
                  fontWeight: 700,
                  color: COLORS.purple,
                }}
              >
                {gpuPercent}%
              </span>
            </div>
            <input
              type="range"
              min="0"
              max="100"
              step="5"
              value={gpuPercent}
              onChange={(e) => setGpuPercent(parseInt(e.target.value))}
              style={{
                width: '100%',
                height: 4,
                borderRadius: 2,
                background: COLORS.border,
                outline: 'none',
                cursor: 'pointer',
                accentColor: COLORS.purple,
              }}
            />
            <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 4 }}>
              0 — 100%
            </div>
          </div>
        </div>
      </Panel>

      {/* Calculated Metrics */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {[
          { label: 'Total Job Minutes', val: Math.round(totalJobMinutes / 1000) + 'k', color: COLORS.text },
          { label: 'GPU Minutes', val: Math.round(gpuMinutes / 1000) + 'k', color: COLORS.purple },
          { label: 'CPU Minutes', val: Math.round(cpuMinutes / 1000) + 'k', color: COLORS.cyan },
          { label: 'Est. Runner Count', val: Math.ceil(totalJobMinutes / 60 / 2000), color: COLORS.yellow },
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
                fontSize: 16,
                fontWeight: 800,
                color: m.color,
                textShadow: `0 0 8px ${m.color}44`,
              }}
            >
              {m.val}
            </div>
          </Panel>
        ))}
      </div>

      {/* Cost Breakdown */}
      <Panel>
        <PanelHeader icon="💰" title="Cost Breakdown" color={COLORS.green} />
        <div style={{ padding: '12px 14px', display: 'flex', gap: 16 }}>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 10, color: COLORS.muted, textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 8 }}>
              GitHub Actions Runner Model
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {[
                { label: 'GitHub Actions (overages)', val: `$${githubActions.toFixed(0)}` },
                { label: 'Self-hosted Runner Infra', val: `$${runnerCosts.toFixed(0)}` },
                { label: 'Network + Storage + Observ', val: `$${infraCosts.toFixed(0)}` },
              ].map((c, i) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: COLORS.textDim }}>
                  <span>{c.label}</span>
                  <span style={{ color: COLORS.text, fontWeight: 700 }}>{c.val}</span>
                </div>
              ))}
            </div>
            <div
              style={{
                marginTop: 8,
                paddingTop: 8,
                borderTop: `1px solid ${COLORS.border}`,
                display: 'flex',
                justifyContent: 'space-between',
              }}
            >
              <span style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>Total Monthly</span>
              <span style={{ fontSize: 16, fontWeight: 800, color: COLORS.yellow }}>
                ${totalGHA.toFixed(0)}
              </span>
            </div>
          </div>

          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 10, color: COLORS.muted, textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: 8 }}>
              RunnerCloud (This Platform)
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {[
                { label: 'Managed inference', val: '–$' + (githubActions * 0.6).toFixed(0) },
                { label: 'Optimized runners', val: '–$' + (runnerCosts * 0.7).toFixed(0) },
                { label: 'Bundled observ', val: '–$' + (infraCosts * 0.5).toFixed(0) },
              ].map((c, i) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: COLORS.green }}>
                  <span>{c.label}</span>
                  <span style={{ color: COLORS.green, fontWeight: 700 }}>{c.val}</span>
                </div>
              ))}
            </div>
            <div
              style={{
                marginTop: 8,
                paddingTop: 8,
                borderTop: `1px solid ${COLORS.border}`,
                display: 'flex',
                justifyContent: 'space-between',
              }}
            >
              <span style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>Monthly Subscription</span>
              <span style={{ fontSize: 16, fontWeight: 800, color: COLORS.green }}>
                ${elevatediqCost.toFixed(0)}
              </span>
            </div>
          </div>

          <div style={{ flex: 0.6, display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'center', gap: 8 }}>
            <div style={{ fontSize: 28, fontWeight: 800, color: COLORS.cyan, textAlign: 'center' }}>
              {savingsPercent}%
            </div>
            <div style={{ fontSize: 10, color: COLORS.muted, textAlign: 'center' }}>
              Savings
            </div>
            <div style={{ fontSize: 14, fontWeight: 700, color: COLORS.green }}>
              ${Math.abs(savings).toFixed(0)}/mo
            </div>
          </div>
        </div>
      </Panel>

      {/* Competitor Comparison */}
      <Panel>
        <PanelHeader icon="📊" title="Competitor Cost Comparison" color={COLORS.accent} />
        <div style={{ padding: '12px 14px' }}>
          <BarChart
            data={[
              { label: 'GitHub Actions', value: totalGHA, color: COLORS.yellow, maxValue: totalGHA * 1.2 },
              { label: 'CircleCI', value: circleci, color: COLORS.blue, maxValue: totalGHA * 1.2 },
              { label: 'Orb CI', value: orbCI, color: COLORS.magenta, maxValue: totalGHA * 1.2 },
              { label: 'Buildkite', value: buildkite, color: COLORS.cyan, maxValue: totalGHA * 1.2 },
              { label: 'RunnerCloud', value: elevatediqCost, color: COLORS.green, maxValue: totalGHA * 1.2 },
            ]}
          />
        </div>
      </Panel>

      {/* Pricing Tiers */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
        {[
          {
            tier: 'Starter',
            price: 499,
            forJobs: '< 500k jobs/month',
            features: ['Shared inference', 'Basic dashboards', 'Email support'],
            highlight: false,
          },
          {
            tier: 'Professional',
            price: 1299,
            forJobs: '500k — 2M jobs/month',
            features: ['Dedicated inference', 'Advanced analytics', 'Slack support'],
            highlight: true,
          },
          {
            tier: 'Enterprise',
            price: 2999,
            forJobs: '> 2M jobs/month',
            features: ['Full-stack optimization', 'Custom SLAs', '24/7 phone support'],
            highlight: false,
          },
        ].map((t) => (
          <Panel key={t.tier} glowColor={t.highlight ? COLORS.green : undefined}>
            <div style={{ padding: '12px 14px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
                <div style={{ fontSize: 13, fontWeight: 800, color: COLORS.text }}>
                  {t.tier}
                </div>
                {t.highlight && (
                  <Pill color="green" sm>
                    Recommended
                  </Pill>
                )}
              </div>
              <div style={{ fontSize: 20, fontWeight: 800, color: COLORS.green, marginBottom: 2 }}>
                ${t.price}
              </div>
              <div style={{ fontSize: 9, color: COLORS.muted, marginBottom: 8 }}>
                {t.forJobs}
              </div>
              <div style={{ fontSize: 10, color: COLORS.textDim, display: 'flex', flexDirection: 'column', gap: 4 }}>
                {t.features.map((f) => (
                  <div key={f} style={{ display: 'flex', gap: 4 }}>
                    <span>✓</span>
                    <span>{f}</span>
                  </div>
                ))}
              </div>
            </div>
          </Panel>
        ))}
      </div>

      {/* Invoice Summary */}
      <Panel>
        <PanelHeader icon="📋" title="Projected Annual Spend" color={COLORS.text} />
        <div style={{ padding: '12px 14px', display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12 }}>
          {[
            { label: 'With GitHub Actions', val: `$${(totalGHA * 12).toFixed(0)}`, color: COLORS.yellow },
            { label: 'RunnerCloud Annual', val: `$${(elevatediqCost * 12).toFixed(0)}`, color: COLORS.green },
            { label: 'Total Annual Savings', val: `$${(savings * 12).toFixed(0)}`, color: COLORS.cyan },
          ].map((i) => (
            <div key={i.label}>
              <div style={{ fontSize: 9, color: COLORS.muted, marginBottom: 4, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                {i.label}
              </div>
              <div style={{ fontSize: 18, fontWeight: 800, color: i.color }}>
                {i.val}
              </div>
            </div>
          ))}
        </div>
      </Panel>
    </div>
  );
};
