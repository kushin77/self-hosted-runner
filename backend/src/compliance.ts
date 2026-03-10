/**
 * Compliance & Policy Service
 * Tracks compliance violations, enforces policies, manages compliance events
 * Supports SOC2, GDPR, and HIPAA compliance requirements
 */

import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

export interface ComplianceViolation {
  id: string;
  eventType: 'policy_violation' | 'rotation_missed' | 'access_denied' | 'audit_divergence';
  resourceType: string;
  resourceId?: string;
  severity: 'critical' | 'high' | 'medium' | 'low';
  status: 'open' | 'acknowledged' | 'resolved';
  details: Record<string, any>;
  remediationSteps?: string[];
  createdAt: Date;
  resolvedAt?: Date;
}

export interface CredentialPolicy {
  id: string;
  name: string;
  description?: string;
  rules: Record<string, any>; // { maxLifetime: 3600, requireRotation: true, etc }
  resourceTypes: string[];
  resourceNames: string[];
  enabled: boolean;
  enforced: boolean;
  createdAt: Date;
  updatedAt: Date;
}

// ============================================================================
// COMPLIANCE SERVICE
// ============================================================================

export class ComplianceService {
  /**
   * Check if credential violates any policy (idempotent)
   */
  async validateCredential(
    credentialName: string,
    credentialType: string,
    credentialValue: string
  ): Promise<{ isCompliant: boolean; violations: ComplianceViolation[] }> {
    try {
      const violations: ComplianceViolation[] = [];

      // Get applicable policies
      const policies = await prisma.credentialPolicy.findMany({
        where: {
          enabled: true,
          resourceTypes: { has: credentialType },
        },
      });

      for (const policy of policies) {
        // Check if policy applies to this credential (glob matching)
        if (!this.matchesPattern(credentialName, policy.resource_names)) {
          continue;
        }

        // Parse rules
        const rules = typeof policy.rules === 'string' ? JSON.parse(policy.rules) : policy.rules;

        // Validate against rules
        if (rules.minLength && credentialValue.length < rules.minLength) {
          violations.push({
            id: `violation-${credentialName}-minLength`,
            eventType: 'policy_violation',
            resourceType: credentialType,
            resourceId: credentialName,
            severity: policy.enforced ? 'critical' : 'high',
            status: 'open',
            details: {
              policy: policy.name,
              rule: 'minLength',
              required: rules.minLength,
              actual: credentialValue.length,
            },
          } as any);
        }

        if (rules.requireSpecialChars && !/[!@#$%^&*]/.test(credentialValue)) {
          violations.push({
            id: `violation-${credentialName}-specialChars`,
            eventType: 'policy_violation',
            resourceType: credentialType,
            resourceId: credentialName,
            severity: 'high',
            status: 'open',
            details: {
              policy: policy.name,
              rule: 'requireSpecialChars',
            },
          } as any);
        }
      }

      // If enforced policy violated, log compliance event
      if (violations.some((v) => v.severity === 'critical')) {
        await this.recordComplianceEvent({
          eventType: 'policy_violation',
          resourceType: credentialType,
          resourceId: credentialName,
          severity: 'critical',
          details: { violations },
        });
        return { isCompliant: false, violations };
      }

      return {
        isCompliant: violations.length === 0,
        violations,
      };
    } catch (error: any) {
      throw new Error(`Failed to validate credential compliance: ${error.message}`);
    }
  }

  /**
   * Ensure credential is rotated within policy timeframe (SOC2 requirement)
   */
  async checkRotationCompliance(
    credentialId: string,
    credentialName: string
  ): Promise<{ isCompliant: boolean; lastRotation: Date; daysSinceRotation: number }> {
    try {
      // Get credential and last rotation
      const credential = await prisma.credential.findUnique({
        where: { id: credentialId },
        include: {
          rotations: {
            orderBy: { rotated_at: 'desc' },
            take: 1,
          },
        },
      });

      if (!credential) {
        throw new Error(`Credential ${credentialId} not found`);
      }

      const lastRotation = credential.rotations[0]?.rotated_at || credential.created_at;
      const daysSinceRotation = Math.floor(
        (Date.now() - lastRotation.getTime()) / (1000 * 60 * 60 * 24)
      );

      // Policy: rotate every 90 days (configurable)
      const maxDaysBeforeRotation = 90;
      const isCompliant = daysSinceRotation <= maxDaysBeforeRotation;

      if (!isCompliant) {
        await this.recordComplianceEvent({
          eventType: 'rotation_missed',
          resourceType: 'credential',
          resourceId: credentialName,
          severity: 'high',
          details: {
            lastRotation,
            daysSinceRotation,
            maxDaysBeforeRotation,
          },
        });
      }

      return {
        isCompliant,
        lastRotation,
        daysSinceRotation,
      };
    } catch (error: any) {
      throw new Error(`Failed to check rotation compliance: ${error.message}`);
    }
  }

  /**
   * Create compliance policy (idempotent - upsert)
   */
  async createPolicy(policy: Omit<CredentialPolicy, 'id' | 'createdAt' | 'updatedAt'>): Promise<CredentialPolicy> {
    try {
      const created = await prisma.credentialPolicy.upsert({
        where: { name: policy.name },
        create: {
          ...policy,
          rules: typeof policy.rules === 'string' ? policy.rules : JSON.stringify(policy.rules),
        },
        update: {
          ...policy,
          rules: typeof policy.rules === 'string' ? policy.rules : JSON.stringify(policy.rules),
        },
      });

      return {
        id: created.id,
        name: created.name,
        description: created.description || undefined,
        rules: JSON.parse(created.rules),
        resourceTypes: created.resource_types,
        resourceNames: created.resource_names,
        enabled: created.enabled,
        enforced: created.enforced,
        createdAt: created.created_at,
        updatedAt: created.updated_at,
      };
    } catch (error: any) {
      throw new Error(`Failed to create policy: ${error.message}`);
    }
  }

  /**
   * Record compliance violation (immutable)
   */
  async recordComplianceEvent(event: {
    eventType: string;
    resourceType: string;
    resourceId?: string;
    severity: string;
    details: Record<string, any>;
    remediationSteps?: string[];
  }): Promise<ComplianceViolation> {
    try {
      const created = await prisma.complianceEvent.create({
        data: {
          event_type: event.eventType,
          resource_type: event.resourceType,
          resource_id: event.resourceId,
          severity: event.severity,
          status: 'open',
          details: JSON.stringify(event.details),
          remediation: event.remediationSteps
            ? JSON.stringify(event.remediationSteps)
            : undefined,
        },
      });

      return {
        id: created.id,
        eventType: created.event_type as any,
        resourceType: created.resource_type,
        resourceId: created.resource_id || undefined,
        severity: created.severity as any,
        status: created.status as any,
        details: JSON.parse(created.details),
        remediationSteps: created.remediation ? JSON.parse(created.remediation) : undefined,
        createdAt: created.created_at,
        resolvedAt: created.resolved_at || undefined,
      };
    } catch (error: any) {
      throw new Error(`Failed to record compliance event: ${error.message}`);
    }
  }

  /**
   * Get compliance status dashboard (summary)
   */
  async getComplianceStatus(): Promise<{
    totalViolations: number;
    openViolations: number;
    criticalViolations: number;
    complianceScore: number; // 0-100
    policies: number;
    enforcedPolicies: number;
  }> {
    try {
      const violations = await prisma.complianceEvent.findMany({
        where: { status: 'open' },
      });

      const criticalCount = violations.filter((v) => v.severity === 'critical').length;
      const policies = await prisma.credentialPolicy.findMany();
      const enforcedCount = policies.filter((p) => p.enforced).length;

      // Simple compliance score: (violations resolved / total violations) * 100
      const allViolations = await prisma.complianceEvent.findMany();
      const resolvedCount = allViolations.filter((v) => v.status === 'resolved').length;
      const complianceScore =
        allViolations.length > 0 ? Math.round((resolvedCount / allViolations.length) * 100) : 100;

      return {
        totalViolations: allViolations.length,
        openViolations: violations.length,
        criticalViolations: criticalCount,
        complianceScore,
        policies: policies.length,
        enforcedPolicies: enforcedCount,
      };
    } catch (error: any) {
      throw new Error(`Failed to get compliance status: ${error.message}`);
    }
  }

  /**
   * Helper: Check if credential name matches policy patterns (glob matching)
   */
  private matchesPattern(credentialName: string, patterns: string[]): boolean {
    for (const pattern of patterns) {
      // Simple glob: "prod-*" matches "prod-db-password"
      const regex = new RegExp(
        '^' + pattern.replace(/\*/g, '.*').replace(/\?/g, '.') + '$'
      );
      if (regex.test(credentialName)) {
        return true;
      }
    }
    return false;
  }
}

// ============================================================================
// SINGLETON INSTANCE
// ============================================================================

let instance: ComplianceService | null = null;

export function getComplianceService(): ComplianceService {
  if (!instance) {
    instance = new ComplianceService();
  }
  return instance;
}

export default ComplianceService;
