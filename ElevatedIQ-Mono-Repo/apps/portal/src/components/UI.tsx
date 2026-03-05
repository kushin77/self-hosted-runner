import React from 'react';
import { COLORS, COLORS_DARK, ColorKey, Theme } from '../theme';

/**
 * Pill - Status/label badge component
 */
interface PillProps {
  color?: ColorKey | string;
  children: React.ReactNode;
  sm?: boolean;
  pulse?: boolean;
}

export const Pill: React.FC<PillProps> = ({ color, children, sm, pulse }) => {
  const colorMap: Record<string, string> = {
    green: COLORS.green,
    yellow: COLORS.yellow,
    red: COLORS.red,
    blue: COLORS.accent,
    purple: COLORS.purple,
    cyan: COLORS.cyan,
    gray: COLORS.muted,
    orange: COLORS.orange,
  };

  const c = (color && (colorMap as Record<string, string>)[String(color)]) || String(color) || COLORS.muted;

  return (
    <span
      style={{
        background: '#f3f6fb',
        color: c,
        border: `1px solid ${COLORS.border}`,
        borderRadius: 6,
        padding: sm ? '2px 6px' : '4px 10px',
        fontSize: sm ? 11 : 12,
        fontWeight: 600,
        letterSpacing: '0.02em',
        whiteSpace: 'nowrap',
        display: 'inline-block',
        animation: pulse ? 'pulse 1.6s infinite' : undefined,
      }}
    >
      {children}
    </span>
  );
};

/**
 * GlowDot - Animated indicator dot
 */
interface GlowDotProps {
  color: string;
  size?: number;
}

export const GlowDot: React.FC<GlowDotProps> = ({ color, size = 7 }) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: '50%',
      background: color,
      boxShadow: `0 0 6px rgba(16,24,40,0.06)`,
      flexShrink: 0,
    }}
  />
);

/**
 * Panel - Main container component with gradient + glow
 */
interface PanelProps {
  children: React.ReactNode;
  style?: React.CSSProperties;
  glowColor?: string;
  variant?: string;
  color?: string;
}

export const Panel: React.FC<PanelProps> = ({ children, style = {}, glowColor, variant, color }) => (
  <div
    style={{
      background: COLORS.surface,
      border: `1px solid ${color || (glowColor ? COLORS.borderBright : COLORS.border)}`,
      borderRadius: 8,
      boxShadow: '0 1px 3px rgba(16,24,40,0.06), 0 1px 2px rgba(16,24,40,0.04)',
      ...style,
    }}
  >
    {children}
  </div>
);

/**
 * Button - Primary button component
 */
interface ButtonProps {
  children: React.ReactNode;
  onClick?: () => void;
  color?: string;
  sm?: boolean;
  style?: React.CSSProperties;
}

/**
 * Global CSS animations and styles
 */
export const GlobalStyles = ({ theme = 'light' }: { theme?: Theme } = {}) => {
  const colors = theme === 'light' ? COLORS : COLORS_DARK;
  
  return (
    <style>{`
      @keyframes spin { to { transform: rotate(360deg); } }
      @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.6; } }
      @keyframes slideIn { from { transform: translateX(400px); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
      
      :root {
        --color-bg: ${colors.bg};
        --color-surface: ${colors.surface};
        --color-surface-high: ${colors.surfaceHigh};
        --color-border: ${colors.border};
        --color-border-bright: ${colors.borderBright};
        --color-accent: ${colors.accent};
        --color-text: ${colors.text};
        --color-text-dim: ${colors.textDim};
        --color-muted: ${colors.muted};
      }
      
      html, body, #root { height: 100%; }
      body {
        margin: 0;
        font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial;
        background: ${colors.bg};
        color: ${colors.text};
        -webkit-font-smoothing: antialiased;
        transition: background 0.3s ease, color 0.3s ease;
      }
      button { font-family: inherit; }
      a { color: ${colors.accent}; text-decoration: none; }
      a:hover { text-decoration: underline; }
      :focus { outline: 2px solid ${colors.accent}; outline-offset: 2px; }
    `}</style>
  );
};

/**
 * PanelHeader - Standard header for panels
 */
interface PanelHeaderProps {
  icon: string;
  title: string;
  right?: React.ReactNode;
  color?: string;
}

export const PanelHeader: React.FC<PanelHeaderProps> = ({ icon, title, right, color }) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '12px 16px',
      borderBottom: `1px solid ${COLORS.border}`,
      background: `linear-gradient(90deg, ${COLORS.accent}08, transparent)`,
    }}
  >
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <span style={{ fontSize: 15, fontWeight: 700 }}>{icon}</span>
      <h3 style={{ fontSize: 14, fontWeight: 700, margin: 0, color: color || COLORS.text }}>{title}</h3>
    </div>
    {right && <div>{right}</div>}
  </div>
);

/**
 * Button - Primary button component
 */
interface ButtonProps {
  children: React.ReactNode;
  onClick?: () => void;
  color?: string;
  sm?: boolean;
  style?: React.CSSProperties;
}

export const Button: React.FC<ButtonProps> = ({ children, onClick, color = COLORS.accent, sm = false, style = {} }) => (
  <button
    onClick={onClick}
    style={{
      background: color,
      border: `1px solid ${color}`,
      color: '#ffffff',
      borderRadius: 6,
      padding: sm ? '6px 12px' : '8px 16px',
      fontSize: sm ? 12 : 13,
      fontWeight: 600,
      cursor: 'pointer',
      transition: 'all 150ms ease',
      ...style,
    }}
    onMouseDown={(e) => {
      (e.currentTarget as HTMLButtonElement).style.transform = 'translateY(1px) scale(0.97)';
    }}
    onMouseUp={(e) => {
      (e.currentTarget as HTMLButtonElement).style.transform = 'translateY(0) scale(1)';
    }}
  >
    {children}
  </button>
);

/**
 * Card - Flexible container for data
 */
interface CardProps {
  children: React.ReactNode;
  padding?: number;
  hoverEffect?: boolean;
  style?: React.CSSProperties;
}

export const Card: React.FC<CardProps> = ({ children, padding = 16, hoverEffect, style = {} }) => (
  <div
    style={{
      background: COLORS.surface,
      border: `1px solid ${COLORS.border}`,
      borderRadius: 8,
      padding,
      boxShadow: '0 1px 3px rgba(16,24,40,0.06)',
      transition: hoverEffect ? 'all 150ms ease' : 'none',
      cursor: hoverEffect ? 'pointer' : 'default',
      ...style,
    }}
    onMouseEnter={(e) => {
      if (hoverEffect) {
        (e.currentTarget as HTMLElement).style.boxShadow = '0 6px 18px rgba(11,95,255,0.06)';
        (e.currentTarget as HTMLElement).style.transform = 'translateY(-2px)';
      }
    }}
    onMouseLeave={(e) => {
      if (hoverEffect) {
        (e.currentTarget as HTMLElement).style.boxShadow = '0 1px 3px rgba(16,24,40,0.06)';
        (e.currentTarget as HTMLElement).style.transform = 'translateY(0)';
      }
    }}
  >
    {children}
  </div>
);

/**
 * Badge - Semantic status badge
 */
interface BadgeProps {
  children: React.ReactNode;
  variant?: 'primary' | 'success' | 'warning' | 'danger';
}

export const Badge: React.FC<BadgeProps> = ({ children, variant = 'primary' }) => {
  const variantMap = {
    primary: { bg: COLORS.accent + '12', color: COLORS.accent },
    success: { bg: COLORS.green + '12', color: COLORS.green },
    warning: { bg: COLORS.yellow + '12', color: COLORS.yellow },
    danger: { bg: COLORS.red + '12', color: COLORS.red },
  };

  const v = variantMap[variant];

  return (
    <span
      style={{
        display: 'inline-block',
        background: v.bg,
        color: v.color,
        padding: '4px 10px',
        borderRadius: 6,
        fontSize: 11,
        fontWeight: 700,
      }}
    >
      {children}
    </span>
  );
};

/**
 * FormControl - Form field wrapper with label and error
 */
interface FormControlProps {
  label?: string;
  error?: string;
  children: React.ReactNode;
  required?: boolean;
  id?: string;
}

export const FormControl: React.FC<FormControlProps> = ({ label, error, children, required, id }) => (
  <div style={{ marginBottom: 16 }}>
    {label && (
      <label
        htmlFor={id}
        style={{
          display: 'block',
          fontSize: 12,
          fontWeight: 600,
          color: COLORS.text,
          marginBottom: 6,
        }}
      >
        {label}
        {required && <span style={{ color: COLORS.red }}>*</span>}
      </label>
    )}
    {children}
    {error && (
      <div style={{ marginTop: 4, fontSize: 11, color: COLORS.red, fontWeight: 500 }} role="alert">
        {error}
      </div>
    )}
  </div>
);

/**
 * Spinner - Loading indicator
 */
export const Spinner: React.FC = () => (
  <div
    style={{
      display: 'inline-block',
      width: 16,
      height: 16,
      border: `2px solid ${COLORS.border}`,
      borderTop: `2px solid ${COLORS.accent}`,
      borderRadius: '50%',
      animation: 'spin 0.8s linear infinite',
    }}
    role="status"
    aria-label="Loading"
  />
);

/**
 * ProgressBar - Horizontal progress bar
 */
interface ProgressBarProps {
  value: number;
  max?: number;
  color?: string;
  showLabel?: boolean;
}

export const ProgressBar: React.FC<ProgressBarProps> = ({ value, max = 100, color = COLORS.accent, showLabel }) => {
  const percent = Math.min(100, (value / max) * 100);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <div
        style={{
          flex: 1,
          height: 6,
          background: COLORS.border,
          borderRadius: 6,
          overflow: 'hidden',
        }}
      >
        <div
          style={{
            height: '100%',
            background: color,
            width: `${percent}%`,
            transition: 'width 200ms ease',
            borderRadius: 6,
          }}
        />
      </div>
      {showLabel && (
        <span style={{ fontSize: 11, fontWeight: 600, color: COLORS.text, minWidth: 30 }}>
          {percent.toFixed(0)}%
        </span>
      )}
    </div>
  );
};

// Re-export chart components
export { AreaChart, BarChart, Gauge, Donut, Sparkline } from './Charts';
