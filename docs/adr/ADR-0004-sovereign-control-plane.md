# ADR 0004: Sovereign Control Plane Independence

**Status**: Proposed
**Date**: 2026-03-05
**Authors**: @platform-architects

## Context

EIQ Nexus must operate independently of external CI/CD platforms and remain functional even when integrations are unavailable.

## Decision

Treat external CI/CD systems as execution engines and integrations only. Design Nexus to continue core operations, analysis, and governance without relying on external availability.

## Rationale

This preserves sovereignty, reduces blast radius from third-party outages, and ensures consistent behavior across environments.

## Consequences

- Positive: Robustness and predictable governance under outages.
- Negative: Need to implement local emulation/queues and more robust state management.
