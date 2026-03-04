import React from 'react';
import { COLORS } from '../theme';

/**
 * Sparkline - Minimal line chart for metrics
 */
interface SparklineProps {
  data: number[];
  color?: string;
  height?: number;
  width?: number;
}

export const Sparkline: React.FC<SparklineProps> = ({
  data,
  color = COLORS.accent,
  height = 32,
  width = 120,
}) => {
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
      <polyline
        points={pts}
        fill="none"
        stroke={color}
        strokeWidth={1.5}
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
};

/**
 * AreaChart - Filled area chart with gradient
 */
interface AreaChartProps {
  data: number[];
  color?: string;
  height?: number;
  width?: number;
}

export const AreaChart: React.FC<AreaChartProps> = ({
  data,
  color = COLORS.accent,
  height = 80,
  width = 300,
}) => {
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
      <polygon
        points={`${first[0]},${height} ${pts} ${last[0]},${height}`}
        fill={`url(#${gradientId})`}
      />
      <polyline
        points={pts}
        fill="none"
        stroke={color}
        strokeWidth={2}
        style={{ filter: `drop-shadow(0 0 4px ${color})` }}
        vectorEffect="non-scaling-stroke"
      />
      <circle
        cx={last[0]}
        cy={last[1]}
        r={3}
        fill={color}
        style={{ filter: `drop-shadow(0 0 6px ${color})` }}
      />
    </svg>
  );
};

/**
 * BarChart - Animated bar chart
 */
interface BarChartProps {
  data: number[] | { label: string; value: number; color?: string; maxValue?: number }[];
  color?: string;
  height?: number;
}

export const BarChart: React.FC<BarChartProps> = ({
  data,
  color = COLORS.accent,
  height = 50,
}) => {
  const normalized = Array.isArray(data) && data.length && typeof (data[0] as any) === 'object'
    ? (data as { label: string; value: number; color?: string; maxValue?: number }[]).map((d) => d.value)
    : (data as number[]);
  const max = Math.max(...normalized);
  const bw = 8,
    gap = 4;
  const w = normalized.length * (bw + gap);

  return (
    <svg width={w} height={height}>
      {normalized.map((v, i) => {
        const bh = (v / max) * (height - 4);
        return (
          <rect
            key={i}
            x={i * (bw + gap)}
            y={height - bh}
            width={bw}
            height={bh}
            fill={Array.isArray(data) && data.length && typeof (data[0] as any) === 'object' ? ((data as any)[i].color || color) : color}
            rx={2}
            opacity={0.7 + (i / normalized.length) * 0.3}
            style={{ filter: `drop-shadow(0 0 4px ${color})` }}
          />
        );
      })}
    </svg>
  );
};

/**
 * Gauge - Half-circle progress gauge
 */
interface GaugeProps {
  value: number;
  max: number;
  color?: string;
  label: string;
  sub?: string;
}

export const Gauge: React.FC<GaugeProps> = ({
  value,
  max,
  color = COLORS.accent,
  label,
  sub,
}) => {
  const pct = value / max;
  const r = 36;
  const cx = 44;
  const cy = 44;
  const circumference = Math.PI * r; // half circle
  const arc = circumference * pct;


  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
      <svg width={88} height={52}>
        <path
          d={`M ${cx - r} ${cy} A ${r} ${r} 0 0 1 ${cx + r} ${cy}`}
          fill="none"
          stroke={COLORS.border}
          strokeWidth={8}
          strokeLinecap="round"
        />
        <path
          d={`M ${cx - r} ${cy} A ${r} ${r} 0 0 1 ${cx + r} ${cy}`}
          fill="none"
          stroke={color}
          strokeWidth={8}
          strokeLinecap="round"
          strokeDasharray={`${arc} ${circumference}`}
          style={{ filter: `drop-shadow(0 0 6px ${color})` }}
        />
        <text
          x={cx}
          y={cy - 2}
          textAnchor="middle"
          fill={color}
          fontSize={16}
          fontWeight={800}
          style={{ fontFamily: 'monospace' }}
        >
          {value}%
        </text>
      </svg>
      <div style={{ fontSize: 11, color: COLORS.text, fontWeight: 600, marginTop: -4 }}>
        {label}
      </div>
      {sub && (
        <div style={{ fontSize: 10, color: COLORS.muted, marginTop: 2 }}>
          {sub}
        </div>
      )}
    </div>
  );
};

/**
 * Donut Chart - Multi-segment donut
 */
interface DonutSegment {
  pct: number;
  color: string;
}

interface DonutProps {
  segments?: DonutSegment[];
  data?: { name: string; value: number; color?: string }[];
}

export const Donut: React.FC<DonutProps> = ({ segments, data }) => {
  const normalizedSegments: DonutSegment[] = segments
    ? segments
    : (data || []).map((d) => ({ pct: d.value, color: d.color || COLORS.accent }));
  const cx = 60;
  const cy = 60;
  const r = 44;
  const stroke = 14;
  let offset = 0;
  const circ = 2 * Math.PI * r;
  return (
    <svg width={120} height={120}>
      {normalizedSegments.map((s, i) => {
        const dash = (s.pct / 100) * circ;
        const el = (
          <circle
            key={i}
            cx={cx}
            cy={cy}
            r={r}
            fill="none"
            stroke={s.color}
            strokeWidth={stroke}
            strokeDasharray={`${dash} ${circ}`}
            strokeDashoffset={(-offset * circ) / 100}
            strokeLinecap="butt"
            style={{ filter: `drop-shadow(0 0 5px ${s.color}88)` }}
            transform={`rotate(-90 ${cx} ${cy})`}
          />
        );
        offset += s.pct;
        return el;
      })}
      <circle cx={cx} cy={cy} r={r - stroke / 2 - 4} fill={COLORS.bg} />
    </svg>
  );
};

/**
 * ProgressBar - Horizontal progress indicator
 */
interface ProgressBarProps {
  value: number;
  max?: number;
  color?: string;
  height?: number;
  showLabel?: boolean;
}

export const ProgressBar: React.FC<ProgressBarProps> = ({
  value,
  max = 100,
  color = COLORS.green,
  height = 4,
  showLabel = true,
}) => {
  const pct = Math.min((value / max) * 100, 100);
  const fillColor = pct > 85 ? COLORS.red : pct > 60 ? COLORS.yellow : color;

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      <div style={{ width: 60, height, background: COLORS.border, borderRadius: 2 }}>
        <div
          style={{
            width: `${pct}%`,
            height: '100%',
            background: fillColor,
            borderRadius: 2,
            transition: 'width 0.3s ease',
          }}
        />
      </div>
      {showLabel && (
        <span style={{ fontSize: 11, color: COLORS.textDim, minWidth: 28, textAlign: 'right' }}>
          {Math.round(pct)}%
        </span>
      )}
    </div>
  );
};
