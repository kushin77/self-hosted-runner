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
    style={{
      background: COLORS.surface,
      border: `1px solid ${glowColor ? COLORS.borderBright : COLORS.border}`,
      borderRadius: 8,
      boxShadow: '0 1px 3px rgba(16,24,40,0.06), 0 1px 2px rgba(16,24,40,0.04)',
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
    borderRadius: 6,
    padding: sm ? '6px 10px' : '8px 16px',
    fontSize: sm ? 12 : 13,
    fontWeight: 600,
    cursor: 'pointer',
    letterSpacing: '0.02em',
    boxShadow: '0 1px 2px rgba(16,24,40,0.06)',
    transition: 'transform 120ms ease, box-shadow 120ms ease',
    ...style,
  };

  return (
    <button
      style={baseStyle}
      onClick={onClick}
      onMouseDown={(e) => (e.currentTarget.style.transform = 'translateY(1px)')}
      onMouseUp={(e) => (e.currentTarget.style.transform = 'translateY(0)')}
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
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.6; }
    }
    
    /* Global typographic and element resets for enterprise look */
    html, body, #root { height: 100%; }
    body { margin: 0; font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial; background: ${COLORS.bg}; color: ${COLORS.text}; -webkit-font-smoothing:antialiased; }
    button { font-family: inherit; }
    a { color: ${COLORS.accent}; text-decoration: none; }
    a:hover { text-decoration: underline; }
    :focus { outline: 2px solid ${COLORS.accent}; outline-offset: 2px; }
  `}</style>
);

// Re-export ProgressBar for convenience (many pages import from UI)
export { ProgressBar } from './Charts';
