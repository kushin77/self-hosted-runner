/**
 * RunnerCloud Portal - Enterprise Design System & Colors
 * Neutral, professional palette with high readability and subtle elevation
 */

export const COLORS = {
  // Core backgrounds (light, enterprise-friendly)
  bg: '#f5f7fa',
  surface: '#ffffff',
  surfaceHigh: '#f0f2f5',

  // Borders
  border: '#e6e9ef',
  borderBright: '#d0d5dd',

  // Primary accent (brand blue)
  accent: '#0b5fff',

  // Status colors
  green: '#0f9d58',
  yellow: '#f6c343',
  red: '#d93025',
  purple: '#6f42c1',
  cyan: '#0891b2',
  orange: '#f97316',

  // Aliases for legacy keys used across components
  blue: '#0b5fff',
  magenta: '#6f42c1',

  // Text
  muted: '#607088',
  text: '#0b1a2b',
  textDim: '#7b8794',
} as const;

export type ColorKey = keyof typeof COLORS;

// Utility function for random numbers
export const rand = (min: number, max: number): number =>
  Math.floor(Math.random() * (max - min + 1)) + min;

// Status to color mapping
export const statusColorMap = {
  active: COLORS.green,
  idle: COLORS.muted,
  running: COLORS.green,
  provisioning: COLORS.yellow,
  draining: COLORS.red,
  pending: COLORS.yellow,
  failed: COLORS.red,
  success: COLORS.green,
  queued: COLORS.yellow,
} as const;

// Mode to color mapping
export const modeColorMap = {
  managed: COLORS.accent,
  byoc: COLORS.cyan,
  onprem: COLORS.purple,
} as const;

/* Additional design tokens for JS consumption */
export const THEME = {
  spacing: {
    xs: 4,
    sm: 8,
    md: 16,
    lg: 24,
    xl: 32,
  },
  radii: {
    sm: 6,
    md: 8,
    lg: 12,
  },
  typography: {
    fontFamily: "Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial",
    sizeBase: 13,
    sizeLg: 16,
    weight: {
      regular: 400,
      medium: 600,
      bold: 800,
    },
  },
  shadows: {
    sm: '0 1px 3px rgba(16,24,40,0.06)',
    md: '0 6px 18px rgba(11,95,255,0.06)'
  }
} as const;
