import React from 'react';
import { COLORS, ColorKey } from './theme';

/**
 * Pill - Status/label badge component
 */
interface PillProps {
  color: 'green' | 'yellow' | 'red' | 'blue' | 'purple' | 'cyan' | 'gray' | 'orange';
  children: React.ReactNode;
  sm?: boolean;
  pulse?: boolean;
}

export const Pill: React.FC<PillProps> = ({ color, children, sm, pulse }) => {
  const colorMap = {
    green: COLORS.green,
    yellow: COLORS.yellow,
    red: COLORS.red,
    blue: COLORS.accent,
    purple: COLORS.purple,
    cyan: COLORS.cyan,
    gray: COLORS.muted,
    orange: COLORS.orange,
  };

  const c = colorMap[color] || COLORS.muted;

  return (
    <span
      style={{
        background: c + '22',
        color: c,
        border: `1px solid ${c}44`,
        borderRadius: 3,
        padding: sm ? '1px 5px' : '2px 8px',
        fontSize: sm ? 9 : 10,
        fontWeight: 700,
        letterSpacing: '0.05em',
        whiteSpace: 'nowrap',
        animation: pulse ? 'pulse 2s infinite' : undefined,
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
      boxShadow: `0 0 8px ${color}`,
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
      background: 'linear-gradient(145deg,#0d1117,#0a0f1a)',
      border: `1px solid ${glowColor ? COLORS.borderBright : COLORS.border}`,
      borderRadius: 10,
      boxShadow: glowColor
        ? `0 0 20px ${glowColor}18, inset 0 1px 0 #ffffff08`
        : 'inset 0 1px 0 #ffffff06',
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
      <span style={{ fontSize: 13, filter: `drop-shadow(0 0 5px ${color})` }}>
        {icon}
      </span>
      <span
        style={{
          fontSize: 11,
          fontWeight: 700,
          color,
          textTransform: 'uppercase',
          letterSpacing: '0.08em',
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
    background: color + '22',
    border: `1px solid ${color}55`,
    color,
    borderRadius: 6,
    padding: sm ? '4px 10px' : '7px 14px',
    fontSize: sm ? 10 : 11,
    fontWeight: 700,
    cursor: 'pointer',
    letterSpacing: '0.04em',
    ...style,
  };

  return (
    <button style={baseStyle} onClick={onClick}>
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
      border: `2px solid ${COLORS.border}`,
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
      50% { opacity: 0.5; }
    }
    @keyframes glow {
      0%, 100% { box-shadow: 0 0 8px rgba(59, 130, 246, 0.5); }
      50% { box-shadow: 0 0 20px rgba(59, 130, 246, 0.8); }
    }
  `}</style>
);
