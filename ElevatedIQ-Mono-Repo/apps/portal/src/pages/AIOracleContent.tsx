import React, { useState } from 'react';
import { COLORS } from '../theme';
import { Panel, PanelHeader, Pill } from '../components/UI';
import { Sparkline } from '../components/Charts';

/**
 * AI Insight Interface
 */
export interface AIInsight {
  id: string;
  title: string;
  severity: 'info' | 'warn' | 'high' | 'critical';
  category: 'performance' | 'cost' | 'reliability' | 'security';
  description: string;
  recommendation: string;
  impact: string;
  implemented?: boolean;
  historicalData?: number[];
}

/**
 * AI Insights Database
 */
const AI_INSIGHTS: AIInsight[] = [
  {
    id: 'flaky-tests-1',
    title: 'Flaky Test Suite Detected',
    severity: 'high',
    category: 'reliability',
    description:
      'Test suite "frontend/e2e" has 18% failure rate but passes when re-run. Suggests timing issues or resource contention.',
    recommendation:
      'Increase timeouts by 2s and implement retry logic. Consider moving to dedicated runner pool.',
    impact: '~$1,200/month in wasted compute cycles',
    implemented: true,
    historicalData: [22, 20, 18, 17, 18, 16, 14, 12, 11],
  },
  {
    id: 'cache-miss-1',
    title: 'Cache Hit Rate Below Threshold',
    severity: 'warn',
    category: 'cost',
    description:
      'npm cache hit rate dropped to 62% (target: 85%). New packages in monorepo dependencies not cached.',
    recommendation:
      'Pre-warm cache with top 100 npm packages. Consider longer TTL (30d → 45d) for stable packages.',
    impact: '~$600/month in unnecessary npm downloads',
    historicalData: [82, 84, 78, 68, 65, 64, 62, 61, 60],
  },
  {
    id: 'gpu-underutil',
    title: 'GPU Runners Underutilized',
    severity: 'info',
    category: 'cost',
    description:
      'GPU runners are idle 40% of the time. Current allocation is 8 GPUs but usage peaks at 4-5.',
    recommendation:
      'Switch to on-demand GPU provisioning. Save $1,200/month by provisioning only during peak hours (9am-6pm UTC).',
    impact: '~$1,200/month in unnecessary GPU costs',
    historicalData: [35, 38, 42, 40, 40, 39, 41, 40, 40],
  },
  {
    id: 'dep-vuln-1',
    title: 'New CVE in Log4j Transitive',
    severity: 'critical',
    category: 'security',
    description:
      'CVE-2024-50379 (CVSS 9.8) found in transitive dependency via Apache Beam. Any job pulling this version is vulnerable.',
    recommendation:
      'Upgrade Apache Beam to ≥2.56.0. Update all pinned transitive dependencies. Run SBOM scan on all jobs.',
    impact: 'Critical: Potential RCE in private code',
    implemented: true,
    historicalData: [0, 0, 0, 0, 0, 0, 1, 1, 1],
  },
  {
    id: 'runner-age',
    title: 'Runner Fleet Aging',
    severity: 'warn',
    category: 'reliability',
    description:
      '23 runners haven\'t been recycled in 120+ days. Accumulated dependency cruft and kernel patches missing.',
    recommendation:
      'Implement weekly rolling restart policy. Current fleet can handle 2-3 machines offline during rotation.',
    impact: '~5% increased job failure rate, security gaps',
    historicalData: [30, 45, 60, 75, 90, 105, 115, 120, 124],
  },
  {
    id: 'api-latency',
    title: 'GitHub API Rate Limit Approaching',
    severity: 'warn',
    category: 'performance',
    description:
      'Making 4,200 API calls/hour (limit: 5,000). Sustain at this rate will hit limits within 2 hours.',
    recommendation:
      'Implement request batching for artifact uploads. Cache branch info for 5 minutes. Expected reduction: 35%.',
    impact: '~8% increase in job duration if limits hit',
    historicalData: [2100, 2800, 3400, 3800, 4100, 4050, 4200, 4150, 4180],
  },
];

/**
 * AI Oracle Page - ML-powered insights for CI/CD optimization
 */
export const AIOraclePageContent: React.FC = () => {
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [filterCategory, setFilterCategory] = useState<'all' | 'performance' | 'cost' | 'reliability' | 'security'>('all');
  const [filterSeverity, setFilterSeverity] = useState<'all' | 'info' | 'warn' | 'high' | 'critical'>('all');

  const filteredInsights = AI_INSIGHTS.filter((i) => {
    const matchCategory = filterCategory === 'all' || i.category === filterCategory;
    const matchSeverity = filterSeverity === 'all' || i.severity === filterSeverity;
    return matchCategory && matchSeverity;
  });

  const severityColorMap = {
    info: COLORS.blue,
    warn: COLORS.yellow,
    high: COLORS.red,
    critical: COLORS.red,
  };

  const categoryIconMap = {
    performance: '⚡',
    cost: '💰',
    reliability: '✓',
    security: '🛡',
  };

  const totalPotentialSavings = AI_INSIGHTS.filter((i) => i.category === 'cost')
    .reduce((sum, i) => {
      const match = i.impact.match(/\$(\d+,?\d*)/);
      return sum + (match ? parseInt(match[1].replace(',', '')) : 0);
    }, 0);

  return (
    <div style={{ flex: 1, padding: 20, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* Header */}
      <div>
        <div style={{ fontSize: 18, fontWeight: 800, color: COLORS.text, marginBottom: 4 }}>
          AI Oracle
        </div>
        <div style={{ fontSize: 12, color: COLORS.muted }}>
          ML-powered insights for optimization · Performance, Cost, Reliability, Security
        </div>
      </div>

      {/* Stats Summary */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {[
          {
            label: 'Active Insights',
            val: AI_INSIGHTS.length,
            color: COLORS.cyan,
          },
          {
            label: 'Critical Issues',
            val: AI_INSIGHTS.filter((i) => i.severity === 'critical').length,
            color: COLORS.red,
          },
          {
            label: 'Potential Monthly Savings',
            val: `$${(totalPotentialSavings / 1000).toFixed(1)}k`,
            color: COLORS.green,
          },
          {
            label: 'Recommendations Implemented',
            val: `${Math.round((AI_INSIGHTS.filter((i) => i.implemented).length / AI_INSIGHTS.length) * 100)}%`,
            color: COLORS.green,
          },
        ].map((s) => (
          <Panel key={s.label} style={{ padding: '12px 14px' }}>
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
                fontSize: 20,
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

      {/* Filters */}
      <div style={{ display: 'flex', gap: 12 }}>
        <div>
          <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
            Category
          </div>
          <div style={{ display: 'flex', gap: 6 }}>
            {(['all', 'performance', 'cost', 'reliability', 'security'] as const).map((c) => (
              <button
                key={c}
                onClick={() => setFilterCategory(c)}
                style={{
                  background: filterCategory === c ? COLORS.accent + '22' : 'transparent',
                  border: filterCategory === c ? `1px solid ${COLORS.accent}` : `1px solid ${COLORS.border}`,
                  color: filterCategory === c ? COLORS.accent : COLORS.textDim,
                  borderRadius: 4,
                  padding: '4px 10px',
                  fontSize: 10,
                  cursor: 'pointer',
                  fontWeight: filterCategory === c ? 700 : 400,
                  textTransform: 'capitalize',
                }}
              >
                {c}
              </button>
            ))}
          </div>
        </div>

        <div>
          <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
            Severity
          </div>
          <div style={{ display: 'flex', gap: 6 }}>
            {(['all', 'info', 'warn', 'high', 'critical'] as const).map((s) => (
              <button
                key={s}
                onClick={() => setFilterSeverity(s)}
                style={{
                  background: filterSeverity === s ? severityColorMap[s === 'all' ? 'info' : s] + '22' : 'transparent',
                  border:
                    filterSeverity === s
                      ? `1px solid ${severityColorMap[s === 'all' ? 'info' : s]}`
                      : `1px solid ${COLORS.border}`,
                  color: filterSeverity === s ? severityColorMap[s === 'all' ? 'info' : s] : COLORS.textDim,
                  borderRadius: 4,
                  padding: '4px 10px',
                  fontSize: 10,
                  cursor: 'pointer',
                  fontWeight: filterSeverity === s ? 700 : 400,
                  textTransform: 'capitalize',
                }}
              >
                {s}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Insights List */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {filteredInsights.map((insight) => (
          <Panel
            key={insight.id}
            style={{
              padding: 0,
              border: `1px solid ${severityColorMap[insight.severity]}22`,
              background:
                expandedId === insight.id
                  ? severityColorMap[insight.severity] + '08'
                  : severityColorMap[insight.severity] + '04',
            }}
          >
            <div
              onClick={() => setExpandedId(expandedId === insight.id ? null : insight.id)}
              style={{
                display: 'flex',
                gap: 12,
                padding: '12px 14px',
                cursor: 'pointer',
                alignItems: 'flex-start',
              }}
            >
              <div
                style={{
                  fontSize: 20,
                  flexShrink: 0,
                }}
              >
                {categoryIconMap[insight.category]}
              </div>

              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                  <div style={{ fontSize: 12, fontWeight: 700, color: COLORS.text }}>
                    {insight.title}
                  </div>
                  <Pill color={insight.severity} sm>
                    {insight.severity}
                  </Pill>
                  {insight.implemented && (
                    <Pill color="green" sm>
                      ✓ Implemented
                    </Pill>
                  )}
                </div>
                <div style={{ fontSize: 11, color: COLORS.textDim, lineHeight: 1.5 }}>
                  {insight.description}
                </div>

                {/* Sparkline for historical data */}
                {insight.historicalData && (
                  <div style={{ marginTop: 6, marginBottom: 4 }}>
                    <Sparkline data={insight.historicalData} color={severityColorMap[insight.severity]} />
                  </div>
                )}

                <div style={{ fontSize: 10, color: severityColorMap[insight.severity], marginTop: 4 }}>
                  💡 Impact: {insight.impact}
                </div>
              </div>

              <span style={{ fontSize: 12, color: COLORS.textDim, flexShrink: 0 }}>
                {expandedId === insight.id ? '▲' : '▼'}
              </span>
            </div>

            {/* Expanded Details */}
            {expandedId === insight.id && (
              <div
                style={{
                  borderTop: `1px solid ${COLORS.border}`,
                  padding: '12px 14px',
                  background: '#000',
                }}
              >
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  <div>
                    <div style={{ fontSize: 10, color: COLORS.muted, marginBottom: 6, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                      Recommendation
                    </div>
                    <div style={{ fontSize: 11, color: COLORS.textDim, lineHeight: 1.6 }}>
                      {insight.recommendation}
                    </div>
                  </div>

                  <div style={{ display: 'flex', gap: 8 }}>
                    <button
                      style={{
                        flex: 1,
                        background: severityColorMap[insight.severity],
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
                      Apply Recommendation
                    </button>
                    <button
                      style={{
                        flex: 1,
                        background: COLORS.border,
                        color: COLORS.text,
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
                      View Details
                    </button>
                  </div>
                </div>
              </div>
            )}
          </Panel>
        ))}
      </div>

      {/* Empty State */}
      {filteredInsights.length === 0 && (
        <Panel
          style={{
            padding: 32,
            textAlign: 'center',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: 8,
          }}
        >
          <div style={{ fontSize: 32 }}>✨</div>
          <div style={{ fontSize: 12, color: COLORS.text, fontWeight: 700 }}>
            No insights match your filters
          </div>
          <div style={{ fontSize: 11, color: COLORS.muted }}>
            Try adjusting category or severity filters
          </div>
        </Panel>
      )}
    </div>
  );
};

export const AIOracleContent: React.FC = AIOraclePageContent;
