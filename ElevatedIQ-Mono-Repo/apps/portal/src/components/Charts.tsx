import React from 'react';
import { COLORS } from '../theme';

type BarDatum = number | { label?: string; value: number; color?: string; maxValue?: number };

interface SparklineProps {
  data: number[];
  color?: string;
  height?: number;
  width?: number;
}

export const Sparkline: React.FC<SparklineProps> = ({ data, color = COLORS.accent, height = 32, width = 120 }) => {
  if (!data || data.length < 2) return null;
  const max = Math.max(...data);
  const min = Math.min(...data);
  const pts = data
    .map((v, i) => {
      const x = (i / (data.length - 1)) * width;
      const y = height - ((v - min) / (max - min || 1)) * (height - 4) - 2;
      return `${x},${y}`;
    })
    .join(' ');

  return (
    <svg width={width} height={height} style={{ display: 'block' }}>
      <polyline points={pts} fill="none" stroke={color} strokeWidth={1.5} vectorEffect="non-scaling-stroke" />
    </svg>
  );
};

interface AreaChartProps {
  data: number[];
  color?: string;
  height?: number;
  width?: number;
}

export const AreaChart: React.FC<AreaChartProps> = ({ data, color = COLORS.accent, height = 80, width = 300 }) => {
  if (!data || data.length < 2) return null;
  const max = Math.max(...data) * 1.1;
  const min = 0;
  const pts = data
    .map((v, i) => {
      const x = (i / (data.length - 1)) * width;
      const y = height - 4 - ((v - min) / (max - min)) * (height - 8);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(' ');
  const first = pts.split(' ')[0].split(',');
  const last = pts.split(' ').slice(-1)[0].split(',');
  const gradientId = `areagrad-${Math.random().toString(36).slice(2)}`;
  return (
    <svg width="100%" viewBox={`0 0 ${width} ${height}`} preserveAspectRatio="none" style={{ overflow: 'visible' }}>
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.35" />
          <stop offset="100%" stopColor={color} stopOpacity="0.03" />
        </linearGradient>
      </defs>
      <polygon points={`${first[0]},${height} ${pts} ${last[0]},${height}`} fill={`url(#${gradientId})`} />
      <polyline points={pts} fill="none" stroke={color} strokeWidth={2} style={{ filter: `drop-shadow(0 0 4px ${color})` }} vectorEffect="non-scaling-stroke" />
      <circle cx={last[0]} cy={last[1]} r={3} fill={color} style={{ filter: `drop-shadow(0 0 6px ${color})` }} />
    </svg>
  );
};

/**
 * BarChart - Animated bar chart
 */
interface BarChartProps {
  data: BarDatum[];
  color?: string;
  height?: number;
}

export const BarChart: React.FC<BarChartProps> = ({ data, color = COLORS.accent, height = 50 }) => {
  // normalize to values and optional per-bar colors
  const values = data.map((d) => (typeof d === 'number' ? d : d.value));
  const colors = data.map((d) => (typeof d === 'number' ? color : d.color || color));
  const maxFromDatum = data.map((d) => (typeof d === 'number' ? undefined : (d as any).maxValue)).filter(Boolean) as number[];
  const globalMax = maxFromDatum.length ? Math.max(...maxFromDatum) : Math.max(...values);
  const bw = 8,
    gap = 4;
  const w = values.length * (bw + gap);
  return (
    <svg width={w} height={height}>
      {values.map((v, i) => {
        const bh = (v / (globalMax || 1)) * (height - 4);
        const fill = colors[i] || color;
        return (
          <rect
            key={i}
            x={i * (bw + gap)}
            y={height - bh}
            width={bw}
            height={bh}
            fill={fill}
            rx={2}
            opacity={0.7 + (i / values.length) * 0.3}
            style={{ filter: `drop-shadow(0 0 4px ${fill})` }}
          />
        );
      })}
    </svg>
  );
};

interface GaugeProps {
  value: number;
  max: number;
  color?: string;
  label: string;
  sub?: string;
}

export const Gauge: React.FC<GaugeProps> = ({ value, max, color = COLORS.accent, label, sub }) => {
  const pct = value / max;
  const r = 36;
  const cx = 44;
  const cy = 44;
  const circumference = Math.PI * r; // half circle
  const arc = circumference * pct;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <svg width={88} height={52}>
        <path d={`M ${cx - r} ${cy} A ${r} ${r} 0 0 1 ${cx + r} ${cy}`} fill="none" stroke={COLORS.border} strokeWidth={8} strokeLinecap="round" />
        <path d={`M ${cx - r} ${cy} A ${r} ${r} 0 0 1 ${cx + r} ${cy}`} fill="none" stroke={color} strokeWidth={8} strokeLinecap="round" strokeDasharray={`${arc} ${circumference}`} style={{ filter: `drop-shadow(0 0 6px ${color})` }} />
        <text x={cx} y={cy - 2} textAnchor="middle" fill={color} fontSize={16} fontWeight={800} style={{ fontFamily: 'monospace' }}>{value}%</text>
      </svg>
      <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 600, marginTop: -4 }}>{label}</div>
      {sub && <div style={{ fontSize: 10, color: COLORS.muted, marginTop: 2 }}>{sub}</div>}
    </div>
  );
};

/**
 * Donut Chart - Multi-segment donut
 */
interface DonutSegment {
  pct?: number;
  value?: number;
  color: string;
}

interface DonutProps {
  segments?: DonutSegment[];
  data?: { name?: string; value: number; color?: string }[]; // legacy pages pass `data`
}

export const Donut: React.FC<DonutProps> = ({ segments = [], data }) => {
  // if `data` provided, convert to segments with pct
  let segs: DonutSegment[] = segments;
  if (data && data.length) {
    const total = data.reduce((s, d) => s + (d.value || 0), 0) || 1;
    segs = data.map((d) => ({ pct: ((d.value || 0) / total) * 100, color: d.color || COLORS.accent }));
  } else if (segments && segments.length && segments[0].value !== undefined) {
    const total = (segments as DonutSegment[]).reduce((s, d) => s + ((d.value as number) || 0), 0) || 1;
    segs = (segments as DonutSegment[]).map((d) => ({ pct: ((d.value as number || 0) / total) * 100, color: d.color }));
  }
  const cx = 60;
  const cy = 60;
  const r = 44;
  const stroke = 14;
  let offset = 0;
  const circ = 2 * Math.PI * r;
  return (
    <svg width={120} height={120}>
      {segs.map((s, i) => {
        const pct = s.pct || 0;
        const dash = (pct / 100) * circ;
        const el = (
          <circle key={i} cx={cx} cy={cy} r={r} fill="none" stroke={s.color} strokeWidth={stroke} strokeDasharray={`${dash} ${circ}`} strokeDashoffset={(-offset * circ) / 100} strokeLinecap="butt" style={{ filter: `drop-shadow(0 0 5px ${s.color}88)` }} transform={`rotate(-90 ${cx} ${cy})`} />
        );
        offset += pct;
        return el;
      })}
      <circle cx={cx} cy={cy} r={r - stroke / 2 - 4} fill={COLORS.bg} />
    </svg>
  );
};

interface ProgressBarProps { value: number; max?: number; color?: string; height?: number; showLabel?: boolean; }
export const ProgressBar: React.FC<ProgressBarProps> = ({ value, max = 100, color = COLORS.green, height = 4, showLabel = true }) => {
  const pct = Math.min((value / max) * 100, 100);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      <div style={{ width: 60, height, background: COLORS.border, borderRadius: 2 }}>
        <div style={{ width: `${pct}%`, height: '100%', background: color ?? (pct > 85 ? COLORS.red : pct > 60 ? COLORS.yellow : COLORS.green), borderRadius: 2, transition: 'width 0.3s ease' }} />
      </div>
      {showLabel && <span style={{ fontSize: 11, color: COLORS.textDim, minWidth: 28, textAlign: 'right' }}>{Math.round(pct)}%</span>}
    </div>
  );
};

/**
 * Donut Chart - Multi-segment donut
 */
/* trailing duplicate Donut and ProgressBar removed (definitions exist above) */
