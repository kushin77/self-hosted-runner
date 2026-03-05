# ADR 0003: API-First Design Mandate

**Status**: Proposed
**Date**: 2026-03-05
**Authors**: @platform-architects

## Context

EIQ Nexus must provide consistent, automatable interfaces for UI, CLI, and AI agents. Avoid UI-only features and ensure automation parity.

## Decision

Mandate API-first development: every feature must have a well-documented API, and the UI/CLI must consume the same APIs. APIs must be stable, versioned, and include observability.

## Rationale

This ensures automation, testing, and AI-driven operations can rely on programmatic access and reduces the risk of hidden functionality.

## Consequences

- Positive: Better automation, easier testing, consistent integrations.
- Negative: Additional upfront design effort for every feature.
