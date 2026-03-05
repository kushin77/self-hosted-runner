/**
 * EIQ Nexus Repair Engine - Safety Guardrail implementation
 * Implements docs/AI_AGENT_SAFETY_FRAMEWORK.md
 */

import { RepairProposal } from '../../../api/nexus/v1/repair';

export const evaluateRisk = (proposal: RepairProposal): 'green' | 'yellow' | 'red' => {
  // AI safety rules per our governance framework:
  // Green - Minimal risk, documented change, no critical paths.
  // Yellow - Significant changes, may need human eyes but likely safe.
  // Red - High-impact, security-sensitive, or complex.

  if (proposal.confidenceLevel < 0.7) return 'red';
  if (proposal.proposedFix.includes('security') || proposal.proposedFix.includes('credential')) return 'red';
  if (proposal.proposedFix.length > 1000) return 'yellow';

  return 'green';
};

export const canAutoApply = (risk: 'green' | 'yellow' | 'red'): boolean => {
  return risk === 'green';
};
