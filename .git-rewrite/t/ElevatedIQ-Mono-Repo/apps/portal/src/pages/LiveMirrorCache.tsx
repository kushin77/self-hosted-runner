import React, { useState, useEffect } from 'react';
import { COLORS } from '../theme';
import { Panel, PanelHeader, Pill } from '../components/UI';
import { Donut } from '../components/Charts';
import { api } from '../api';

/**
 * Cache Layer Interface
 */
export interface CacheLayer {
  name: string;
  type: 'npm' | 'pip' | 'maven' | 'docker' | 'gradle' | 'nuget';
  hitRate: number;
  size: number;
  sizeGB: string;
  items: number;
  lastWarmup: string;
  ttl: string;
  color: string;
}

/**
 * Cache Layers
 */
const EMPTY_CACHE: CacheLayer[] = [];

/**
 * Popular Packages in Cache
 */
const TOP_PACKAGES = [
  { name: '@babel/core', size: '12MB', hits: 12400, layer: 'npm' },
  { name: 'tensorflow', size: '340MB', hits: 8900, layer: 'pip' },
  { name: 'maven-surefire-plugin', size: '45MB', hits: 6700, layer: 'maven' },
  { name: 'node:18-alpine', size: '180MB', hits: 14200, layer: 'docker' },
  { name: 'spring-boot-starter-web', size: '35MB', hits: 5600, layer: 'maven' },
  { name: 'androidx', size: '28MB', hits: 4300, layer: 'gradle' },
];

/**
 * Cache Warmup Strategy
 */
interface WarmupStrategy {
  name: string;
  frequency: string;
  packages: number;
  expectedGain: string;
  estimatedCost: string;
}

const WARMUP_STRATEGIES: WarmupStrategy[] = [
  {
    name: 'Aggressive (Recommended)',
    frequency: 'Every 6 hours',
    packages: 850,
    expectedGain: '+8-12% hit rate',
    estimatedCost: '$12/month',
  },
  {
    name: 'Balanced',
    frequency: 'Daily',
    packages: 450,
    expectedGain: '+4-6% hit rate',
    estimatedCost: '$4/month',
  },
  {
    name: 'Minimal',
    frequency: 'Weekly',
    packages: 200,
    expectedGain: '+1-2% hit rate',
    estimatedCost: '$0/month',
  },
];

/**
 * LiveMirror Cache Page
 */
export const LiveMirrorCache: React.FC = () => {
  const [expandedLayer, setExpandedLayer] = useState<string | null>(null);
  const [selectedStrategy, setSelectedStrategy] = useState<number>(0);
  const [layers, setLayers] = useState<CacheLayer[]>(EMPTY_CACHE);

  useEffect(() => {
    let mounted = true;
    api
      .getCacheLayers()
      .then((c: any[]) => {
        if (!mounted) return;
        const mapped: CacheLayer[] = c.map((l, idx) => ({
          name: l.name || `layer-${idx}`,
          type: l.type || 'npm',
          hitRate: l.hitRate ?? 0,
          size: l.size ?? 0,
          sizeGB: l.sizeGB || (l.size ? `${(l.size / 1024).toFixed(1)}GB` : '0GB'),
          items: l.items ?? 0,
          lastWarmup: l.lastWarmup || 'unknown',
          ttl: l.ttl || '30 days',
          color: l.color || COLORS.border,
        }));
        setLayers(mapped);
      })
      .catch(() => setLayers([]));

    return () => { mounted = false; };
  }, []);

  const totalHitRate = layers.length ? Math.round(layers.reduce((sum, c) => sum + c.hitRate, 0) / layers.length) : 0;
  const totalSize = layers.reduce((sum, c) => sum + (c.size || 0), 0);
  const totalItems = layers.reduce((sum, c) => sum + (c.items || 0), 0);

  const monthlySavings = Math.round((totalHitRate / 100) * 2400); // Approx savings

  return (
    <div style={{ flex: 1, padding: 20, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* Header */}
      <div>
        <div style={{ fontSize: 18, fontWeight: 800, color: COLORS.text, marginBottom: 4 }}>
          LiveMirror Cache
        </div>
        <div style={{ fontSize: 12, color: COLORS.muted }}>
          Multi-layer dependency caching · npm, pip, maven, docker, gradle, nuget
        </div>
      </div>

      {/* Key Metrics */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
        {[
          { label: 'Overall Hit Rate', val: `${totalHitRate}%`, color: COLORS.green },
          { label: 'Total Cache Size', val: `${(totalSize / 1024).toFixed(1)}TB`, color: COLORS.cyan },
          { label: 'Cached Items', val: totalItems.toLocaleString(), color: COLORS.yellow },
          { label: 'Monthly Savings', val: `$${monthlySavings}`, color: COLORS.green },
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

      {/* Cache Composition */}
      <Panel>
        <PanelHeader icon="📦" title="Cache Composition" color={COLORS.yellow} />
        <div style={{ padding: '10px 14px' }}>
          <Donut
            segments={layers.map((c) => ({ value: c.size, color: c.color }))}
          />
        </div>
      </Panel>

      {/* Cache Layers */}
      <Panel>
        <PanelHeader icon="🔄" title="Cache Layers Status" color={COLORS.cyan} />
        <div style={{ padding: '8px 14px', display: 'flex', flexDirection: 'column', gap: 4 }}>
          {layers.map((layer) => (
            <div
              key={layer.name}
              onClick={() => setExpandedLayer(expandedLayer === layer.name ? null : layer.name)}
              style={{
                background:
                  expandedLayer === layer.name ? layer.color + '12' : '#00000020',
                border: `1px solid ${layer.color}44`,
                borderRadius: 6,
                padding: '8px 10px',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                gap: 8,
              }}
            >
              <div
                style={{
                  width: 24,
                  height: 24,
                  borderRadius: '50%',
                  background: layer.color,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 10,
                  fontWeight: 800,
                  color: '#000',
                }}
              >
                {layer.hitRate}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                  {layer.name}
                </div>
                <div style={{ fontSize: 9, color: COLORS.muted }}>
                  {layer.sizeGB} · {layer.items.toLocaleString()} items · {layer.ttl} TTL
                </div>
              </div>
              <Pill color={layer.hitRate > 85 ? 'green' : layer.hitRate > 75 ? 'yellow' : 'red'} sm>
                {layer.hitRate}%
              </Pill>
              <span style={{ fontSize: 12, color: COLORS.textDim }}>
                {expandedLayer === layer.name ? '▲' : '▼'}
              </span>
            </div>
          ))}

          {/* Expanded Details */}
          {expandedLayer && (
            <div
              style={{
                background: '#000',
                border: `1px solid ${COLORS.border}`,
                borderRadius: 6,
                padding: '10px',
                marginTop: 4,
              }}
            >
              {(() => {
                const layer = layers.find((l) => l.name === expandedLayer);
                return layer ? (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
                      {[
                        { label: 'Hit Rate', val: `${layer.hitRate}%` },
                        { label: 'Last Warmup', val: layer.lastWarmup },
                        { label: 'TTL Setting', val: layer.ttl },
                      ].map((item) => (
                        <div key={item.label}>
                          <div style={{ fontSize: 9, color: COLORS.muted, marginBottom: 2 }}>
                            {item.label}
                          </div>
                          <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                            {item.val}
                          </div>
                        </div>
                      ))}
                    </div>
                    <button
                      style={{
                        background: layer.color,
                        color: '#000',
                        border: 'none',
                        borderRadius: 4,
                        padding: '6px 12px',
                        fontSize: 10,
                        fontWeight: 700,
                        cursor: 'pointer',
                        textTransform: 'uppercase',
                        letterSpacing: '0.05em',
                      }}
                    >
                      Warm Cache Now
                    </button>
                  </div>
                ) : null;
              })()}
            </div>
          )}
        </div>
      </Panel>

      {/* Top Packages in Cache */}
      <Panel>
        <PanelHeader icon="⭐" title="Top Packages in Cache" color={COLORS.yellow} />
        <div style={{ padding: '8px 14px', display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {TOP_PACKAGES.map((pkg, i) => (
            <div
              key={i}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                padding: '6px 0',
                borderBottom:
                  i < TOP_PACKAGES.length - 1
                    ? `1px solid ${COLORS.border}`
                    : 'none',
              }}
            >
              <div
                style={{
                  width: 20,
                  height: 20,
                  borderRadius: 2,
                  background: COLORS.border,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontSize: 10,
                  fontWeight: 700,
                  color: COLORS.text,
                }}
              >
                {i + 1}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 700 }}>
                  {pkg.name}
                </div>
                <div style={{ fontSize: 9, color: COLORS.muted }}>
                  {pkg.size} • {pkg.hits} hits
                </div>
              </div>
              <Pill color={COLORS.cyan} sm>
                {pkg.layer}
              </Pill>
            </div>
          ))}
        </div>
      </Panel>

      {/* Warmup Strategies */}
      <Panel>
        <PanelHeader icon="🔥" title="Cache Warmup Strategies" color={COLORS.green} />
        <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {WARMUP_STRATEGIES.map((strategy, i) => (
            <div
              key={i}
              onClick={() => setSelectedStrategy(i)}
              style={{
                background: selectedStrategy === i ? COLORS.green + '22' : '#00000020',
                border:
                  selectedStrategy === i
                    ? `2px solid ${COLORS.green}`
                    : `1px solid ${COLORS.border}`,
                borderRadius: 6,
                padding: '10px',
                cursor: 'pointer',
                transition: 'all 0.2s ease',
              }}
            >
              <div
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  marginBottom: 6,
                }}
              >
                <div style={{ fontSize: 12, fontWeight: 700, color: COLORS.text }}>
                  {strategy.name}
                </div>
                {selectedStrategy === i && (
                  <Pill color="green" sm>
                    Selected
                  </Pill>
                )}
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8, fontSize: 10 }}>
                {[
                  { label: 'Frequency', val: strategy.frequency },
                  { label: 'Expected Gain', val: strategy.expectedGain },
                  { label: 'Est. Cost', val: strategy.estimatedCost },
                ].map((item) => (
                  <div key={item.label}>
                    <div style={{ color: COLORS.muted, marginBottom: 2 }}>
                      {item.label}
                    </div>
                    <div style={{ color: COLORS.text, fontWeight: 700 }}>
                      {item.val}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
          <button
            style={{
              background: COLORS.green,
              color: '#000',
              border: 'none',
              borderRadius: 4,
              padding: '8px 12px',
              fontSize: 11,
              fontWeight: 700,
              cursor: 'pointer',
              textTransform: 'uppercase',
              letterSpacing: '0.05em',
              marginTop: 4,
            }}
          >
            Apply Strategy
          </button>
        </div>
      </Panel>

      {/* Recommendations */}
      <Panel glowColor={COLORS.yellow}>
        <PanelHeader icon="💡" title="Optimization Tips" color={COLORS.yellow} />
        <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 6 }}>
          {[
            'npm layer below target: Consider warming top 200 frequently-used packages daily',
            'Maven cache size growing: Implement cache eviction policy for non-production builds',
            'Docker layer hit rate best-in-class: Keep current warmup schedule',
          ].map((tip, i) => (
            <div key={i} style={{ display: 'flex', gap: 8, fontSize: 11 }}>
              <span style={{ color: COLORS.yellow, flexShrink: 0 }}>▶</span>
              <span style={{ color: COLORS.textDim }}>{tip}</span>
            </div>
          ))}
        </div>
      </Panel>
    </div>
  );
};
