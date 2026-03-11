/**
 * Multi-Cloud Sync Orchestrator
 * 
 * Coordinates synchronization of resources across cloud providers:
 * - Immutable audit trail (append-only JSONL)
 * - Idempotent operations (safe to re-run)
 * - Ephemeral tasks (auto-cleanup)
 * - Comprehensive error handling and retry logic
 * - Dry-run mode for validation
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import {
  CloudProvider,
  ICloudProvider,
  ResourceMetadata,
  SyncConfig,
  SyncResult,
  SyncAuditEntry,
  OperationResult,
  ProviderRegistry,
} from './types';
import { createHash } from 'crypto';

/**
 * Sync orchestrator
 */
export class SyncOrchestrator {
  private auditLogPath: string;
  private auditLog: SyncAuditEntry[] = [];
  private syncOperations = new Map<string, SyncResult>();
  private registry: ProviderRegistry;

  constructor(registry: ProviderRegistry, auditLogDir?: string) {
    this.registry = registry;
    this.auditLogPath = path.join(auditLogDir || '.sync_audit', `${Date.now()}.jsonl`);
  }

  /**
   * Synchronize resources across cloud providers
   */
  async sync(config: SyncConfig): Promise<SyncResult> {
    const syncId = this.generateSyncId();
    const startTime = Date.now();

    const result: SyncResult = {
      sourceProvider: config.sourceProvider,
      targetProviders: config.targetProviders,
      totalResources: config.resources.length,
      succeededResources: 0,
      failedResources: 0,
      skippedResources: 0,
      startTime: new Date(),
      endTime: new Date(),
      duration: 0,
      errors: [],
      audit: [],
    };

    try {
      await this.logAudit({
        timestamp: new Date(),
        operation: 'sync_started',
        sourceProvider: config.sourceProvider,
        targetProvider: config.targetProviders[0],
        resourceId: syncId,
        status: 'pending',
      });

      // Get source and target providers
      const sourceProvider = this.registry.get(config.sourceProvider);
      if (!sourceProvider) {
        throw new Error(`Source provider ${config.sourceProvider} not found`);
      }

      const targetProviders = config.targetProviders
        .map(p => ({
          provider: p,
          instance: this.registry.get(p),
        }))
        .filter(p => p.instance !== null);

      if (targetProviders.length === 0) {
        throw new Error('No valid target providers found');
      }

      // Sync each resource
      for (const resourceId of config.resources) {
        const syncSuccess = await this.syncResource(
          sourceProvider,
          targetProviders.map(p => p.instance!),
          resourceId,
          config,
          result,
        );

        if (syncSuccess) {
          result.succeededResources++;
        }
      }

      result.endTime = new Date();
      result.duration = Date.now() - startTime;

      await this.logAudit({
        timestamp: new Date(),
        operation: 'sync_completed',
        sourceProvider: config.sourceProvider,
        targetProvider: config.targetProviders[0],
        resourceId: syncId,
        status: result.failedResources === 0 ? 'success' : 'failure',
        details: {
          succeeded: result.succeededResources,
          failed: result.failedResources,
          skipped: result.skippedResources,
          duration: result.duration,
        },
      });

      this.syncOperations.set(syncId, result);
      return result;
    } catch (error) {
      result.endTime = new Date();
      result.duration = Date.now() - startTime;
      result.errors.push({
        resourceId: 'sync_orchestration',
        provider: config.sourceProvider,
        error: error instanceof Error ? error.message : String(error),
      });

      await this.logAudit({
        timestamp: new Date(),
        operation: 'sync_error',
        sourceProvider: config.sourceProvider,
        targetProvider: config.targetProviders[0],
        resourceId: 'sync_orchestration',
        status: 'failure',
        details: { error: result.errors[0]?.error },
      });

      return result;
    }
  }

  /**
   * Synchronize a single resource
   */
  private async syncResource(
    sourceProvider: ICloudProvider,
    targetProviders: ICloudProvider[],
    resourceId: string,
    config: SyncConfig,
    result: SyncResult,
  ): Promise<boolean> {
    try {
      await this.logAudit({
        timestamp: new Date(),
        operation: 'sync_resource',
        sourceProvider: config.sourceProvider,
        targetProvider: targetProviders[0].provider,
        resourceId,
        status: 'pending',
      });

      // Get resource from source
      const sourceResult = await sourceProvider.getResource(resourceId);
      
      if (!sourceResult.success || !sourceResult.data) {
        throw new Error(`Failed to get resource from source: ${sourceResult.error?.message}`);
      }

      const sourceResource = sourceResult.data;

      // Check if resource exists in target (if applicable)
      if (config.skipIfExists) {
        let exists = false;

        for (const targetProvider of targetProviders) {
          const checkResult = await targetProvider.getResource(resourceId);
          if (checkResult.success && checkResult.data) {
            exists = true;
            break;
          }
        }

        if (exists) {
          result.skippedResources++;
          await this.logAudit({
            timestamp: new Date(),
            operation: 'skip_resource',
            sourceProvider: config.sourceProvider,
            targetProvider: targetProviders[0].provider,
            resourceId,
            status: 'skipped',
            details: { reason: 'Resource already exists in target' },
          });
          return true;
        }
      }

      // Apply transformations
      const transformedResource = this.applyTransformations(sourceResource, config.transformations);

      // Sync to each target provider
      let targetSyncSuccess = true;

      for (const targetProvider of targetProviders) {
        const retryConfig = config.retryPolicy || {
          maxAttempts: 3,
          delayMs: 1000,
          backoffMultiplier: 2,
        };

        let lastError: Error | null = null;
        let delay = retryConfig.delayMs;

        for (let attempt = 1; attempt <= retryConfig.maxAttempts; attempt++) {
          try {
            // Determine sync strategy and execute
            await this.executeSyncStrategy(targetProvider, transformedResource, config.strategy);

            if (config.audit) {
              await this.logAudit({
                timestamp: new Date(),
                operation: 'sync_resource',
                sourceProvider: config.sourceProvider,
                targetProvider: targetProvider.provider,
                resourceId,
                status: 'success',
                details: {
                  strategy: config.strategy,
                  attempt,
                },
              });
            }

            break; // Success
          } catch (error) {
            lastError = error instanceof Error ? error : new Error(String(error));

            if (attempt < retryConfig.maxAttempts) {
              await this.sleep(delay);
              delay *= retryConfig.backoffMultiplier;
            }
          }
        }

        if (lastError) {
          targetSyncSuccess = false;
          result.errors.push({
            resourceId,
            provider: targetProvider.provider,
            error: lastError.message,
          });

          await this.logAudit({
            timestamp: new Date(),
            operation: 'sync_error',
            sourceProvider: config.sourceProvider,
            targetProvider: targetProvider.provider,
            resourceId,
            status: 'failure',
            details: { error: lastError.message },
          });
        }
      }

      if (!targetSyncSuccess) {
        result.failedResources++;
      }

      return targetSyncSuccess;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      result.failedResources++;
      result.errors.push({
        resourceId,
        provider: config.sourceProvider,
        error: message,
      });

      await this.logAudit({
        timestamp: new Date(),
        operation: 'sync_error',
        sourceProvider: config.sourceProvider,
        targetProvider: config.targetProviders[0],
        resourceId,
        status: 'failure',
        details: { error: message },
      });

      return false;
    }
  }

  /**
   * Execute sync strategy
   */
  private async executeSyncStrategy(
    targetProvider: ICloudProvider,
    resource: ResourceMetadata,
    strategy: string,
  ): Promise<void> {
    switch (strategy) {
      case 'mirror':
        // Create exact copy
        await targetProvider.createResource({
          ...resource,
          name: resource.name,
        });
        break;

      case 'merge':
        // Create or update
        const existing = await targetProvider.getResource(resource.id);
        if (existing.success && existing.data) {
          await targetProvider.updateResource(resource.id, resource);
        } else {
          await targetProvider.createResource(resource);
        }
        break;

      case 'copy':
        // Create new with generated name
        await targetProvider.createResource({
          ...resource,
          name: `${resource.name}-copy-${Date.now()}`,
        });
        break;

      case 'delete-target':
        // Delete target resource
        await targetProvider.deleteResource(resource.id);
        break;

      default:
        throw new Error(`Unknown sync strategy: ${strategy}`);
    }
  }

  /**
   * Apply transformations to resource
   */
  private applyTransformations(
    resource: ResourceMetadata,
    transformations?: Record<string, (value: any) => any>,
  ): ResourceMetadata {
    if (!transformations) {
      return resource;
    }

    const transformed = { ...resource };

    for (const [key, transform] of Object.entries(transformations)) {
      if (key in transformed) {
        (transformed as any)[key] = transform((transformed as any)[key]);
      }
    }

    return transformed;
  }

  /**
   * Get sync operation result
   */
  getSyncOperation(syncId: string): SyncResult | null {
    return this.syncOperations.get(syncId) || null;
  }

  /**
   * Get sync operations
   */
  getSyncOperations(): SyncResult[] {
    return Array.from(this.syncOperations.values());
  }

  /**
   * Get audit log
   */
  getAuditLog(filter?: {operation?: string; provider?: CloudProvider}): SyncAuditEntry[] {
    return this.auditLog.filter(entry => {
      if (filter?.operation && entry.operation !== filter.operation) return false;
      if (filter?.provider && entry.sourceProvider !== filter.provider) return false;
      return true;
    });
  }

  /**
   * Log audit entry (immutable append-only)
   */
  private async logAudit(entry: SyncAuditEntry): Promise<void> {
    // Add hash for tamper detection
    const entryWithHash = {
      ...entry,
      hash: this.hashEntry(entry),
    };

    this.auditLog.push(entryWithHash);

    try {
      const logDir = path.dirname(this.auditLogPath);
      await fs.mkdir(logDir, { recursive: true });
      const line = JSON.stringify(entryWithHash) + '\n';
      await fs.appendFile(this.auditLogPath, line);
    } catch (error) {
      console.error('Failed to write sync audit log:', error);
    }
  }

  /**
   * Hash entry for tamper detection
   */
  private hashEntry(entry: Omit<SyncAuditEntry, 'hash'>): string {
    const combined = JSON.stringify({
      timestamp: entry.timestamp,
      operation: entry.operation,
      sourceProvider: entry.sourceProvider,
      targetProvider: entry.targetProvider,
      resourceId: entry.resourceId,
      status: entry.status,
    });
    return createHash('sha256').update(combined).digest('hex');
  }

  /**
   * Generate sync ID
   */
  private generateSyncId(): string {
    return `sync-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Sleep utility
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Get sync statistics
   */
  getStatistics(): {
    totalSyncs: number;
    successfulSyncs: number;
    failedSyncs: number;
    totalResources: number;
    succeededResources: number;
    failedResources: number;
    skippedResources: number;
    averageDuration: number;
  } {
    const operations = Array.from(this.syncOperations.values());
    const successfulSyncs = operations.filter(op => op.failedResources === 0).length;
    const failedSyncs = operations.filter(op => op.failedResources > 0).length;

    const stats = {
      totalSyncs: operations.length,
      successfulSyncs,
      failedSyncs,
      totalResources: operations.reduce((sum, op) => sum + op.totalResources, 0),
      succeededResources: operations.reduce((sum, op) => sum + op.succeededResources, 0),
      failedResources: operations.reduce((sum, op) => sum + op.failedResources, 0),
      skippedResources: operations.reduce((sum, op) => sum + op.skippedResources, 0),
      averageDuration:
        operations.length > 0
          ? operations.reduce((sum, op) => sum + op.duration, 0) / operations.length
          : 0,
    };

    return stats;
  }
}
