/**
 * RunnerCloud Portal - Design System & Colors
 * Dark theme with glowing accents for ultra-modern CI/CD dashboard
 */

export const COLORS = {
  // Core backgrounds
  bg: "#070a0f",
  surface: "#0d1117",
  surfaceHigh: "#111827",

  // Borders
  border: "#1a2236",
  borderBright: "#243050",

  // Primary accent (blue)
  accent: "#3b82f6",
  accentGlow: "#3b82f655",
  // aliases for historical keys used in pages
  blue: "#3b82f6",
  magenta: "#d946ef",

  // Status colors
  green: "#22c55e",
  greenGlow: "#22c55e33",
  yellow: "#f59e0b",
  red: "#ef4444",
  purple: "#a855f7",
  cyan: "#06b6d4",
  orange: "#f97316",

  // Text
  muted: "#4b5563",
  text: "#e2e8f0",
  textDim: "#94a3b8",
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
