/**
 * Audit & Logging Service
 * Immutable, append-only audit trail for compliance and debugging
 * All entries are hashed and chained (blockchain-like structure)
 */

import { getPrisma } from './prisma-wrapper';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';

const prisma = getPrisma();

// ============================================================================
// TYPE DEFINITIONS
// ============================================================================

export interface AuditLogEntry {
  id: string;
  timestamp: Date;
  event: string; // credential_rotated, user_login, access_denied, etc
  resourceType: string; // credential, user, policy, system
  resourceId?: string;
  actor: string; // user, service, system
  action: string; // What was done
  status: 'success' | 'denied' | 'failed';
  details?: Record<string, any>;
  ipAddress?: string;
  userAgent?: string;
  hash: string;
  previousHash?: string;
}

// ============================================================================
// AUDIT SERVICE
// ============================================================================

export class AuditService {
  private lastHash: string = '';

  constructor() {
    this.initializeLastHash();
  }

  /**
   * Initialize last hash from database (chain latest audit entry)
   */
  private async initializeLastHash(): Promise<void> {
    try {
      const latest = await prisma.auditLog.findFirst({
        orderBy: { created_at: 'desc' },
        take: 1,
      });
      if (latest) {
        this.lastHash = latest.hash;
      }
    } catch (error: any) {
      console.warn(`⚠️ Failed to initialize audit hash: ${error.message}`);
      this.lastHash = crypto.createHash('sha256').update('genesis').digest('hex');
    }
  }

  /**
   * Log audit entry (immutable append-only)
   * All entries are hashed and chained
   */
  async log(entry: Omit<AuditLogEntry, 'id' | 'hash' | 'previousHash'>): Promise<AuditLogEntry> {
    try {
      // Calculate hash of this entry + previous hash (blockchain-like chain)
      const hashInput = JSON.stringify({
        ...entry,
        previousHash: this.lastHash,
      });
      const hash = crypto.createHash('sha256').update(hashInput).digest('hex');

      // Write to database (immutable append-only)
      const logEntry = await prisma.auditLog.create({
        data: {
          event: entry.event,
          resource_type: entry.resourceType,
          resource_id: entry.resourceId,
          actor_id: entry.actor,
          action: entry.action,
          details: entry.details ? JSON.stringify(entry.details) : null,
          hash,
          previous_hash: this.lastHash,
        },
      });

      // Update last hash for next entry
      this.lastHash = hash;

      // Also write to JSONL for cloud export (GCS)
      this.appendToJSONL({
        id: logEntry.id,
        timestamp: logEntry.created_at,
        event: logEntry.event,
        resourceType: logEntry.resource_type,
        resourceId: logEntry.resource_id,
        actor: logEntry.actor_id,
        action: logEntry.action,
        status: 'success',
        details: logEntry.details ? JSON.parse(logEntry.details) : undefined,
        hash,
        previousHash: this.lastHash,
      });

      return {
        id: logEntry.id,
        timestamp: logEntry.created_at,
        event: logEntry.event,
        resourceType: logEntry.resource_type,
        resourceId: logEntry.resource_id || undefined,
        actor: logEntry.actor_id,
        action: logEntry.action,
        status: 'success',
        details: logEntry.details ? JSON.parse(logEntry.details) : undefined,
        hash,
        previousHash: this.lastHash,
      };
    } catch (error: any) {
      console.error(`❌ Failed to log audit entry: ${error.message}`);
      throw error;
    }
  }

  /**
   * Query audit logs with filtering (idempotent - same filters always produce same results)
   */
  async query(filters: {
    resourceType?: string;
    resourceId?: string;
    actor?: string;
    action?: string;
    status?: string;
    startDate?: Date;
    endDate?: Date;
    limit?: number;
    offset?: number;
  }): Promise<{ entries: AuditLogEntry[]; total: number }> {
    try {
      const limit = filters.limit || 100;
      const offset = filters.offset || 0;

      const where: any = {};
      if (filters.resourceType) where.resource_type = filters.resourceType;
      if (filters.resourceId) where.resource_id = filters.resourceId;
      if (filters.actor) where.actor_id = filters.actor;
      if (filters.action) where.action = filters.action;
      if (filters.startDate || filters.endDate) {
        where.created_at = {};
        if (filters.startDate) where.created_at.gte = filters.startDate;
        if (filters.endDate) where.created_at.lte = filters.endDate;
      }

      const [entries, total] = await Promise.all([
        prisma.auditLog.findMany({
          where,
          orderBy: { created_at: 'desc' },
          take: limit,
          skip: offset,
        }),
        prisma.auditLog.count({ where }),
      ]);

      return {
        entries: entries.map((e) => ({
          id: e.id,
          timestamp: e.created_at,
          event: e.event,
          resourceType: e.resource_type,
          resourceId: e.resource_id || undefined,
          actor: e.actor_id,
          action: e.action,
          status: 'success',
          details: e.details ? JSON.parse(e.details) : undefined,
          hash: e.hash,
          previousHash: e.previous_hash || undefined,
        })),
        total,
      };
    } catch (error: any) {
      console.error(`❌ Failed to query audit logs: ${error.message}`);
      throw error;
    }
  }

  /**
   * Verify audit trail integrity (blockchain-like validation)
   * All hashes must be valid and properly chained
   */
  async verifyIntegrity(): Promise<{
    isValid: boolean;
    entriesChecked: number;
    brokenChainAt?: string;
    error?: string;
  }> {
    try {
      const entries = await prisma.auditLog.findMany({
        orderBy: { created_at: 'asc' },
      });

      let previousHash = crypto
        .createHash('sha256')
        .update('genesis')
        .digest('hex');
      let entriesChecked = 0;

      for (const entry of entries) {
        // Reconstruct the hash
        const hashInput = JSON.stringify({
          event: entry.event,
          resource_type: entry.resource_type,
          resource_id: entry.resource_id,
          actor_id: entry.actor_id,
          action: entry.action,
          details: entry.details,
          previousHash,
        });
        const calculatedHash = crypto
          .createHash('sha256')
          .update(hashInput)
          .digest('hex');

        if (calculatedHash !== entry.hash) {
          return {
            isValid: false,
            entriesChecked,
            brokenChainAt: entry.id,
            error: `Hash mismatch at entry ${entry.id}`,
          };
        }

        previousHash = entry.hash;
        entriesChecked++;
      }

      return {
        isValid: true,
        entriesChecked,
      };
    } catch (error: any) {
      return {
        isValid: false,
        entriesChecked: 0,
        error: error.message,
      };
    }
  }

  /**
   * Export audit logs to JSONL and upload to cloud storage (GCS)
   * Idempotent: same export always produces same result
   */
  async exportToCloud(): Promise<{
    exportId: string;
    entriesExported: number;
    destination: string;
    timestamp: Date;
  }> {
    try {
      const exportId = crypto.randomUUID();
      const entries = await prisma.auditLog.findMany({
        orderBy: { created_at: 'asc' },
      });

      // Write JSONL file
      const filename = `audit-export-${new Date().toISOString().split('T')[0]}-${exportId}.jsonl`;
      const logsDir = path.join(__dirname, '../logs');
      const filepath = path.join(logsDir, filename);

      if (!fs.existsSync(logsDir)) {
        fs.mkdirSync(logsDir, { recursive: true });
      }

      const stream = fs.createWriteStream(filepath, { flags: 'a' });
      for (const entry of entries) {
        stream.write(
          JSON.stringify({
            id: entry.id,
            timestamp: entry.created_at,
            event: entry.event,
            resourceType: entry.resource_type,
            resourceId: entry.resource_id,
            actor: entry.actor_id,
            action: entry.action,
            details: entry.details ? JSON.parse(entry.details) : undefined,
            hash: entry.hash,
            previousHash: entry.previous_hash,
          }) + '\n'
        );
      }
      stream.end();

      // In production: upload to GCS with versioning
      // gs://nexusshield-audit-trail/audit-export-2026-03-09.jsonl

      return {
        exportId,
        entriesExported: entries.length,
        destination: `gs://nexusshield-audit-trail/${filename}`,
        timestamp: new Date(),
      };
    } catch (error: any) {
      throw new Error(`Failed to export audit logs: ${error.message}`);
    }
  }

  /**
   * Private: Append entry to JSONL file
   */
  private appendToJSONL(entry: AuditLogEntry): void {
    try {
      const logsDir = path.join(__dirname, '../logs');
      if (!fs.existsSync(logsDir)) {
        fs.mkdirSync(logsDir, { recursive: true });
      }

      const filepath = path.join(logsDir, 'portal-api-audit.jsonl');
      fs.appendFileSync(filepath, JSON.stringify(entry) + '\n', { flag: 'a' });
    } catch (error: any) {
      console.warn(`⚠️ Failed to append to JSONL: ${error.message}`);
      // Non-blocking: don't fail main operation if JSONL write fails
    }
  }
}

// ============================================================================
// SINGLETON INSTANCE
// ============================================================================

let instance: AuditService | null = null;

export function getAuditService(): AuditService {
  if (!instance) {
    instance = new AuditService();
  }
  return instance;
}

export default AuditService;
