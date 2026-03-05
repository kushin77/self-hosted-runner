import React from 'react';
import { COLORS, ColorKey } from '../theme';

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
  const bgLight = c + '09';

  return (
    <span
      style={{
        background: bgLight,
        color: c,
        border: `1px solid ${c}33`,
        borderRadius: 'var(--radius-sm)',
        padding: sm ? '3px 8px' : '5px 12px',
        fontSize: sm ? 11 : 12,
        fontWeight: 600,
        letterSpacing: '0.02em',
        whiteSpace: 'nowrap',
        display: 'inline-block',
        animation: pulse ? 'pulse 2s ease-in-out infinite' : 'none',
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
}

export const Panel: React.FC<PanelProps> = ({ children, style = {}, glowColor }) => (
  <div
    className="panel"
    style={{
      background: COLORS.surface,
      border: `1px solid ${glowColor ? COLORS.borderBright : COLORS.border}`,
      borderRadius: 'var(--radius-md)',
      boxShadow: glowColor ? `0 0 12px ${glowColor}22, var(--shadow-md)` : 'var(--shadow-sm)',
      transition: 'box-shadow 200ms ease',
      ...style,
    }}
  >
    {children}
  </div>
);

/**
 * PanelHeader - Standard header for panels
 */
interface PanelHeaderProps {
  icon: string;
  title: string;
  color?: string;
  right?: React.ReactNode;
}

export const PanelHeader: React.FC<PanelHeaderProps> = ({
  icon,
  title,
  color = COLORS.accent,
  right,
}) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '11px 16px',
      borderBottom: `1px solid ${COLORS.border}`,
    }}
  >
    <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
      <span style={{ fontSize: 14, color: COLORS.text, fontWeight: 700 }}>{icon}</span>
      <span
        style={{
          fontSize: 13,
          fontWeight: 700,
          color: COLORS.text,
          textTransform: 'none',
          letterSpacing: '0.01em',
        }}
      >
        {title}
      </span>
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

export const Button: React.FC<ButtonProps> = ({
  children,
  onClick,
  color = COLORS.accent,
  sm = false,
  style = {},
}) => {
  const baseStyle: React.CSSProperties = {
    background: color,
    border: `1px solid ${color}`,
    color: '#ffffff',
    borderRadius: 'var(--radius-sm)',
    padding: sm ? '7px 12px' : '10px 18px',
    fontSize: sm ? 12 : 13,
    fontWeight: 600,
    cursor: 'pointer',
    letterSpacing: '0.02em',
    boxShadow: 'var(--shadow-sm)',
    transition: 'all 150ms cubic-bezier(0.2, 0, 0.13, 1.5)',
    ...style,
  };

  return (
    <button
      className="primary"
      style={baseStyle}
      onClick={onClick}
      onMouseDown={(e) => (e.currentTarget.style.transform = 'translateY(1px) scale(0.97)')}
      onMouseUp={(e) => (e.currentTarget.style.transform = 'translateY(0) scale(1)')}
    >
      {children}
    </button>
  );
};

/**
 * Loading spinner
 */
export const Spinner: React.FC = () => (
  <div
    style={{
      display: 'inline-block',
      width: 16,
      height: 16,
      border: `2px solid ${COLORS.borderBright}`,
      borderTop: `2px solid ${COLORS.accent}`,
      borderRadius: '50%',
      animation: 'spin 0.8s linear infinite',
    }}
  />
);

/**
 * Global CSS animations
 */
export const GlobalStyles = () => (
  <style>{`
    /* Keyframes */
    @keyframes spin { to { transform: rotate(360deg); } }
    @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.6; } }

    /* Design tokens exposed as CSS variables for consistency */
    :root {
      --color-bg: ${COLORS.bg};
      --color-surface: ${COLORS.surface};
      --color-surface-high: ${COLORS.surfaceHigh};
      --color-border: ${COLORS.border};
      --color-border-bright: ${COLORS.borderBright};
      --color-accent: ${COLORS.accent};
      --color-text: ${COLORS.text};
      --color-text-dim: ${COLORS.textDim};
      --color-muted: ${COLORS.muted};
      --radius-sm: 6px;
      --radius-md: 8px;
      --radius-lg: 12px;
      --shadow-sm: 0 1px 3px rgba(16,24,40,0.06);
      --shadow-md: 0 6px 18px rgba(11,95,255,0.06);
      --gap-sm: 8px;
      --gap-md: 16px;
      --gap-lg: 24px;
      --max-width: 1200px;
      --font-sans: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial;
      --text-size-base: 13px;
      --text-size-lg: 16px;
      --text-weight-regular: 400;
      --text-weight-medium: 600;
      --text-weight-bold: 800;
    }

    /* Base resets and layout */
    html, body, #root { height: 100%; }
    *, *::before, *::after { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: var(--font-sans);
      font-size: var(--text-size-base);
      background: var(--color-bg);
      color: var(--color-text);
      -webkit-font-smoothing: antialiased;
      -moz-osx-font-smoothing: grayscale;
      line-height: 1.35;
    }

    /* Typography */
    h1, h2, h3, h4, h5, h6 { margin: 0; color: var(--color-text); font-weight: var(--text-weight-bold); }
    h1 { font-size: 20px; }
    h2 { font-size: 16px; }
    p, label, span, a { color: var(--color-text); }
    small, .muted { color: var(--color-text-dim); font-size: 12px; }

    /* Links and focus styles */
    a { color: var(--color-accent); text-decoration: none; }
    a:hover, a:focus { text-decoration: underline; }
    :focus { outline: 3px solid rgba(11,95,255,0.12); outline-offset: 2px; }

    /* Buttons */
    button { font-family: inherit; font-weight: var(--text-weight-medium); border-radius: var(--radius-sm); }
    button:disabled { opacity: 0.6; cursor: not-allowed; }
    button.primary:hover { transform: translateY(-1px); box-shadow: var(--shadow-md); }

    /* Form controls */
    input, textarea, select {
      height: 36px;
      padding: 8px 10px;
      border: 1px solid var(--color-border);
      border-radius: var(--radius-sm);
      background: var(--color-surface);
      color: var(--color-text);
      font-size: 13px;
    }
    textarea { min-height: 96px; padding-top: 10px; }
    input:focus, textarea:focus, select:focus { border-color: var(--color-accent); box-shadow: 0 0 0 3px rgba(11,95,255,0.06); }

    /* Panels, cards, lists */
    .container { max-width: var(--max-width); margin: 0 auto; padding: 0 var(--gap-md); }
    .card, .panel { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); box-shadow: var(--shadow-sm); }
    .card.padded { padding: var(--gap-md); }

    /* Tables */
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    thead th { text-align: left; padding: 10px; font-weight: 600; color: var(--color-text-dim); border-bottom: 1px solid var(--color-border); }
    tbody td { padding: 10px; border-bottom: 1px solid var(--color-surface-high); }

    /* Sidebar helpers */
    .sidebar { background: var(--color-surface); border-right: 1px solid var(--color-border); }
    .sidebar .nav-item { padding: 12px 14px; display:flex; gap:10px; align-items:center; cursor:pointer; color:var(--color-text-dim); }
    .sidebar .nav-item.active { background: linear-gradient(90deg, rgba(11,95,255,0.04), transparent); color: var(--color-accent); font-weight: 700; }

    /* Scrollbars (subtle) */
    ::-webkit-scrollbar { height:10px; width:10px; }
    ::-webkit-scrollbar-thumb { background: linear-gradient(180deg, rgba(11,95,255,0.12), rgba(11,95,255,0.06)); border-radius: 8px; }

    /* Responsive tweaks */
    @media (max-width: 900px) {
      .sidebar { display: none; }
      .container { padding: 0 12px; }
    }

    /* Utility helpers */
    .flex { display:flex; }
    .gap-sm { gap: var(--gap-sm); }
    .gap-md { gap: var(--gap-md); }
    .muted { color: var(--color-text-dim); }
  `}</style>
);

/**
 * FormControl - Input field wrapper with label and error state
 */
interface FormControlProps {
  label?: string;
  error?: string;
  children: React.ReactNode;
  required?: boolean;
  id?: string;
}

export const FormControl: React.FC<FormControlProps> = ({
  label,
  error,
  children,
  required,
  id,
}) => (
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
          letterSpacing: '0.02em',
        }}
      >
        {label}
        {required && <span style={{ color: COLORS.red }}>*</span>}
      </label>
    )}
    {children}
    {error && (
      <div
        style={{
          marginTop: 4,
          fontSize: 11,
          color: COLORS.red,
          fontWeight: 500,
        }}
        role="alert"
      >
        {error}
      </div>
    )}
  </div>
);

/**
 * Card - Simplified container for data display
 */
interface CardProps {
  children: React.ReactNode;
  padding?: number;
  hoverEffect?: boolean;
}

export const Card: React.FC<CardProps> = ({ children, padding = 16, hoverEffect }) => (
  <div
    style={{
      background: COLORS.surface,
      border: `1px solid ${COLORS.border}`,
      borderRadius: 'var(--radius-md)',
      padding,
      boxShadow: 'var(--shadow-sm)',
      transition: hoverEffect ? 'all 150ms ease' : 'none',
      cursor: hoverEffect ? 'pointer' : 'default',
    }}
    onMouseEnter={(e) => {
      if (hoverEffect) {
        (e.currentTarget as HTMLElement).style.boxShadow = 'var(--shadow-md)';
        (e.currentTarget as HTMLElement).style.transform = 'translateY(-2px)';
      }
    }}
    onMouseLeave={(e) => {
      if (hoverEffect) {
        (e.currentTarget as HTMLElement).style.boxShadow = 'var(--shadow-sm)';
        (e.currentTarget as HTMLElement).style.transform = 'translateY(0)';
      }
    }}
  >
    {children}
  </div>
);

/**
 * Badge - Simple semantic badge component
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
        borderRadius: 'var(--radius-sm)',
        fontSize: 11,
        fontWeight: 700,
        letterSpacing: '0.02em',
      }}
    >
      {children}
    </span>
  );
};

// Re-export chart components for convenience across pages
export { Sparkline, AreaChart, BarChart, ProgressBar, Gauge, Donut } from './Charts';
