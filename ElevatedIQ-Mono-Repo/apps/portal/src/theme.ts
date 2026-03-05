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
