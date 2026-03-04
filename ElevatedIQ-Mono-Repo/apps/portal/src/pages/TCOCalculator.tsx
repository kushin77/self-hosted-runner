import React, { useState, useMemo, useEffect } from 'react';
import { COLORS } from '../theme';
import { Panel, Button } from '../components/UI';
import { api } from '../api';

interface CostModel {
  name: string;
  color: string;
  calculate: (params: CalculationParams) => number;
  description: string;
}

interface CalculationParams {
  monthlyMinutes: number;
  linuxPercent: number;
  windowsPercent: number;
  macosPercent: number;
  spotUsagePercent: number;
  concurrentRunners: number;
}

/**
 * TCO Calculator - RunnerCloud vs Competitors
 * Helps users visualize cost savings
 */
export const TCOCalculator: React.FC = () => {
  // State
  const [monthlyMinutes, setMonthlyMinutes] = useState(50000);
  const [linuxPercent, setLinuxPercent] = useState(70);
  const [windowsPercent, setWindowsPercent] = useState(20);
  // macOS percent is auto-calculated from other OSes
  const [spotUsagePercent, setSpotUsagePercent] = useState(75);

  // Derived
  const macosPercentAdjusted = Math.max(0, 100 - linuxPercent - windowsPercent);
  const concurrentRunners = Math.ceil(monthlyMinutes / (30 * 60)); // Rough estimate

  const params: CalculationParams = {
    monthlyMinutes,
    linuxPercent,
    windowsPercent,
    macosPercent: macosPercentAdjusted,
    spotUsagePercent,
    concurrentRunners,
  };

  // Initialize settings from billing if available (prefill monthly minutes)
  useEffect(() => {
    let mounted = true;
    (async () => {
      try {
        const billing = await api.getBilling();
        if (!mounted) return;
        if (billing && billing.currentMonth && typeof billing.currentMonth.runnerMinutes === 'number') {
          setMonthlyMinutes(Math.max(1000, Math.round(billing.currentMonth.runnerMinutes)));
        }
      } catch (e) {
        // ignore - keep defaults
      }
    })();

    return () => { mounted = false; };
  }, []);

  // Cost Models
  const costModels: Record<string, CostModel> = {
    runnercloud_managed: {
      name: 'RunnerCloud Managed',
      color: COLORS.accent,
      description: 'SaaS runners with per-second billing',
      calculate: (p) => {
        const linuxCost = (p.monthlyMinutes * p.linuxPercent / 100) * 0.004 / 60;
        const windowsCost = (p.monthlyMinutes * p.windowsPercent / 100) * 0.008 / 60;
        const macosCost = (p.monthlyMinutes * p.macosPercent / 100) * 0.012 / 60;
        return Math.round((linuxCost + windowsCost + macosCost) * 100) / 100;
      },
    },
    runnercloud_byoc: {
      name: 'RunnerCloud BYOC',
      color: COLORS.purple,
      description: '$199/mo control plane + cloud compute',
      calculate: (p) => {
        const controlPlane = 199;
        // Spot instance cost: ~$0.06/hour for t3.xlarge = ~0.001/min
        const linuxSpot = (p.monthlyMinutes * p.linuxPercent / 100 * p.spotUsagePercent / 100) * 0.001;
        const linuxOnDemand = (p.monthlyMinutes * p.linuxPercent / 100 * (100 - p.spotUsagePercent) / 100) * 0.0015;
        const windowsSpot = (p.monthlyMinutes * p.windowsPercent / 100 * p.spotUsagePercent / 100) * 0.002;
        const windowsOnDemand = (p.monthlyMinutes * p.windowsPercent / 100 * (100 - p.spotUsagePercent) / 100) * 0.003;
        return Math.round((controlPlane + linuxSpot + linuxOnDemand + windowsSpot + windowsOnDemand) * 100) / 100;
      },
    },
    github_hosted: {
      name: 'GitHub Hosted',
      color: COLORS.muted,
      description: '$0.008/min for Windows, free Linux (with min spend)',
      calculate: (p) => {
        const linuxCost = p.monthlyMinutes * p.linuxPercent / 100 * 0.0004; // GitHub's effective rate
        const windowsCost = p.monthlyMinutes * p.windowsPercent / 100 * 0.008;
        return Math.round((linuxCost + windowsCost) * 100) / 100;
      },
    },
    blacksmith: {
      name: 'Blacksmith CI',
      color: COLORS.orange,
      description: 'SaaS runners ($0.004/min for all OSes)',
      calculate: (p) => {
        return Math.round(p.monthlyMinutes * 0.004 * 100) / 100;
      },
    },
    buildkite: {
      name: 'Buildkite',
      color: COLORS.green,
      description: '$30/user/mo + self-hosted infra',
      calculate: (p) => {
        const perUser = 30 * 3; // Assume 3 engineers running CI
        const infraCost = (p.monthlyMinutes * 0.001); // Rough estimate for compute
        return Math.round((perUser + infraCost) * 100) / 100;
      },
    },
  };

  // Calculate all costs
  const costs = useMemo(() => {
    const result: Record<string, number> = {};
    Object.entries(costModels).forEach(([key, model]) => {
      result[key] = model.calculate(params);
    });
    return result;
  }, [params]);

  // Find min/max for scaling
  const maxCost = Math.max(...Object.values(costs));
  const minCost = Math.min(...Object.values(costs));
  const costRange = maxCost - minCost;

  // Savings calculations
  const githubCost = costs.github_hosted;
  const runnercloudSavings = githubCost > 0 ? Math.round(((githubCost - costs.runnercloud_managed) / githubCost) * 100) : 0;
  const byocSavings = githubCost > 0 ? Math.round(((githubCost - costs.runnercloud_byoc) / githubCost) * 100) : 0;

  // Slider Component
  const Slider: React.FC<{
    label: string;
    value: number;
    onChange: (val: number) => void;
    min: number;
    max: number;
    step: number;
    unit?: string;
  }> = ({ label, value, onChange, min, max, step, unit = '' }) => (
    <div style={{ marginBottom: 12 }}>
      <div
        style={{
          display: 'flex',
          justifyContent: 'space-between',
          marginBottom: 6,
          fontSize: 11,
          fontWeight: 600,
        }}
      >
        <span style={{ color: COLORS.text }}>{label}</span>
        <span style={{ color: COLORS.accent }}>
          {value.toLocaleString()}{unit}
        </span>
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseInt(e.target.value, 10))}
        style={{
          width: '100%',
          height: 4,
          borderRadius: 2,
          background: COLORS.border,
          cursor: 'pointer',
          accentColor: COLORS.accent,
        }}
      />
      <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 4 }}>
        {min.toLocaleString()} - {max.toLocaleString()}{unit}
      </div>
    </div>
  );

  // Cost Bar Component
  const CostBar: React.FC<{
    model: CostModel;
    cost: number;
  }> = ({ model, cost }) => {
    const width = costRange > 0 ? ((cost - minCost) / costRange) * 100 : 0;
    const savings = githubCost > 0 ? Math.round(((githubCost - cost) / githubCost) * 100) : 0;

    return (
      <div key={model.name} style={{ marginBottom: 16 }}>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            marginBottom: 6,
          }}
        >
          <div>
            <div style={{ fontSize: 11, fontWeight: 700, color: model.color }}>
              {model.name}
            </div>
            <div style={{ fontSize: 9, color: COLORS.muted }}>
              {model.description}
            </div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.text }}>
              ${cost.toFixed(2)}
            </div>
            {savings > 0 && (
              <div style={{ fontSize: 9, color: COLORS.green }}>
                {savings}% vs GitHub
              </div>
            )}
          </div>
        </div>

        <div
          style={{
            height: 8,
            background: COLORS.border,
            borderRadius: 4,
            overflow: 'hidden',
          }}
        >
          <div
            style={{
              width: `${Math.max(width, 5)}%`,
              height: '100%',
              background: model.color,
              transition: 'width 0.3s',
            }}
          />
        </div>
      </div>
    );
  };

  return (
    <div
      style={{
        flex: 1,
        display: 'flex',
        flexDirection: 'column',
        gap: 16,
        padding: 16,
        overflow: 'auto',
      }}
    >
      {/* Header */}
      <div>
        <div style={{ fontSize: 18, fontWeight: 700, color: COLORS.text, marginBottom: 4 }}>
          TCO Calculator
        </div>
        <div style={{ fontSize: 12, color: COLORS.muted }}>
          Compare monthly costs: RunnerCloud vs GitHub Actions vs competitors
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
        {/* Left: Input Controls */}
        <Panel style={{ padding: 16 }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: COLORS.accent, marginBottom: 12 }}>
            WORKLOAD PROFILE
          </div>

          <Slider
            label="Monthly Build Minutes"
            value={monthlyMinutes}
            onChange={setMonthlyMinutes}
            min={1000}
            max={500000}
            step={5000}
            unit=" min"
          />

          <div style={{ marginTop: 16, marginBottom: 12 }}>
            <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.accent }}>
              OS Distribution
            </div>
          </div>

          <Slider
            label="Linux"
            value={linuxPercent}
            onChange={setLinuxPercent}
            min={0}
            max={100}
            step={10}
            unit="%"
          />

          <Slider
            label="Windows"
            value={windowsPercent}
            onChange={setWindowsPercent}
            min={0}
            max={100 - linuxPercent}
            step={10}
            unit="%"
          />

          <Panel
            style={{
              padding: 8,
              background: COLORS.surface,
              border: `1px solid ${COLORS.border}`,
              marginBottom: 12,
            }}
          >
            <div style={{ fontSize: 9, color: COLORS.muted }}>
              macOS: {macosPercentAdjusted}% (auto-calculated)
            </div>
          </Panel>

          <Slider
            label="Spot Instance Usage"
            value={spotUsagePercent}
            onChange={setSpotUsagePercent}
            min={0}
            max={100}
            step={10}
            unit="%"
          />

          {/* Summary */}
          <Panel
            style={{
              padding: 10,
              background: COLORS.accent + '08',
              border: `1px solid ${COLORS.accent}22`,
              marginTop: 16,
            }}
          >
            <div style={{ fontSize: 9, fontWeight: 700, color: COLORS.text, marginBottom: 6 }}>
              ESTIMATED CONCURRENCY
            </div>
            <div style={{ fontSize: 13, fontWeight: 700, color: COLORS.accent }}>
              ~{concurrentRunners} parallel runners
            </div>
            <div style={{ fontSize: 9, color: COLORS.muted, marginTop: 4 }}>
              Based on 30-minute average job time
            </div>
          </Panel>
        </Panel>

        {/* Right: Cost Comparison */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          {/* Cost Bars */}
          <Panel style={{ padding: 16 }}>
            <div style={{ fontSize: 12, fontWeight: 700, color: COLORS.green, marginBottom: 12 }}>
              MONTHLY COST COMPARISON
            </div>

            {Object.entries(costModels)
              .sort(([, a], [, b]) => costs[Object.keys(costModels)[Object.values(costModels).indexOf(a)]] - costs[Object.keys(costModels)[Object.values(costModels).indexOf(b)]])
              .map(([key, model]) => (
                <CostBar key={key} model={model} cost={costs[key]} />
              ))}
          </Panel>

          {/* Savings Highlight */}
          <Panel
            style={{
              padding: 12,
              background: `linear-gradient(135deg, ${COLORS.accent}08, ${COLORS.purple}08)`,
              border: `1px solid ${COLORS.accent}22`,
            }}
          >
            <div style={{ fontSize: 11, fontWeight: 700, color: COLORS.accent, marginBottom: 8 }}>
              RUNNERCLOUD SAVINGS
            </div>
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: '1fr 1fr',
                gap: 8,
              }}
            >
              <div>
                <div style={{ fontSize: 16, fontWeight: 700, color: COLORS.accent }}>
                  {runnercloudSavings}%
                </div>
                <div style={{ fontSize: 9, color: COLORS.muted }}>
                  Managed vs GitHub
                </div>
              </div>
              <div>
                <div style={{ fontSize: 16, fontWeight: 700, color: COLORS.purple }}>
                  {byocSavings}%
                </div>
                <div style={{ fontSize: 9, color: COLORS.muted }}>
                  BYOC vs GitHub
                </div>
              </div>
            </div>
            <Panel
              style={{
                padding: 8,
                background: COLORS.surface,
                border: `1px solid ${COLORS.border}`,
                marginTop: 12,
              }}
            >
              <div style={{ fontSize: 8, color: COLORS.textDim }}>
                💡 Annual savings: ${((githubCost - costs.runnercloud_managed) * 12).toFixed(0)} (Managed) or
                ${((githubCost - costs.runnercloud_byoc) * 12).toFixed(0)} (BYOC)
              </div>
            </Panel>
          </Panel>
        </div>
      </div>

      {/* Assumptions & Methodology */}
      <Panel style={{ padding: 12 }}>
        <div style={{ fontSize: 10, fontWeight: 700, color: COLORS.muted, marginBottom: 8 }}>
          ASSUMPTIONS & PRICING (as of March 2026)
        </div>
        <div style={{ fontSize: 9, color: COLORS.textDim, lineHeight: '1.6', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <div>
            <strong>GitHub Actions:</strong>
            <br />• Linux: $0.0004/min (effectively free)
            <br />• Windows: $0.008/min ($0.48/hr)
            <br />• macOS: $0.016/min ($0.96/hr)
          </div>
          <div>
            <strong>RunnerCloud:</strong>
            <br />• Managed: $0.004/min Linux, $0.008/min Windows
            <br />• BYOC: $199/mo control + spot instances
            <br />• Spot: 40-75% discount vs on-demand
          </div>
          <div>
            <strong>Competitors:</strong>
            <br />• Blacksmith: $0.004/min all OSes
            <br />• Buildkite: $30/user/mo + infrastructure
            <br />• Depot: Plan-based (similar to Blacksmith)
          </div>
          <div>
            <strong>Notes:</strong>
            <br />• Assumes 30-min average job time
            <br />• Spot pricing averages shown
            <br />• Cache benefits not included
          </div>
        </div>
      </Panel>

      {/* Export & Share */}
      <div style={{ display: 'flex', gap: 8 }}>
        <Button
          color={COLORS.cyan}
          onClick={() => {
            const pdfData = `TCO Comparison Report\n\nMonthly Build Minutes: ${monthlyMinutes.toLocaleString()}\nOS Distribution: Linux ${linuxPercent}%, Windows ${windowsPercent}%, macOS ${macosPercentAdjusted}%\n\nMonthly Costs:\n` +
              Object.entries(costModels).map(([key, model]) => `${model.name}: $${costs[key].toFixed(2)}`).join('\n');
            const element = document.createElement('a');
            element.setAttribute('href', 'data:text/plain;charset=utf-8,' + encodeURIComponent(pdfData));
            element.setAttribute('download', 'runnercloud-tco-report.txt');
            element.style.display = 'none';
            document.body.appendChild(element);
            element.click();
            document.body.removeChild(element);
          }}
        >
          📥 Export Report
        </Button>
        <Button
          color={COLORS.cyan}
          onClick={() => {
            alert('Share URL feature coming soon!\nBookmark this page to share your configuration');
          }}
        >
          🔗 Share Config
        </Button>
      </div>
    </div>
  );
};
