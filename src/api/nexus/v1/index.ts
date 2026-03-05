/**
 * EIQ Nexus v1 API - Main Entry Point
 * Implements ADR-0003: API-First Design Mandate
 */

export * from './pipelines';
export * from './runners';
export * from './repair';

export const NEXUS_API_VERSION = 'v1';
export const NEXUS_DOC_URL = 'docs/adr/ADR-0003-api-first-design.md';
