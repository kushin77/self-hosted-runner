/**
 * Base Cloud Provider Implementation
 * 
 * Provides common functionality for all cloud providers:
 * - Lifecycle management (initialize, cleanup)
 * - Credential management
 * - Health checking
 * - Audit logging
 * - Error handling and retries
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import {
  CloudProvider,
  ICloudProvider,
  ProviderCredentials,
  HealthCheckResult,
  OperationResult,
  ResourceMetadata,
  ComputeConfig,
  ComputeStatus,
  StorageConfig,
  NetworkConfig,
  SecurityGroupConfig,
  DatabaseConfig,
  RegionInfo,
  AccountInfo,
  MetricData,
} from './types';
import { CredentialManager } from './credential-manager';

/**
 * Base provider audit entry
 */
interface ProviderAuditEntry {
  timestamp: Date;
  operation: string;
  success: boolean;
  message: string;
  error?: string;
  duration: number; // milliseconds
  details?: Record<string, any>;
}

/**
 * Retry configuration
 */
interface RetryConfig {
  maxAttempts: number;
  delayMs: number;
  backoffMultiplier: number;
}

/**
 * Base class for all cloud providers
 */
export abstract class BaseCloudProvider implements ICloudProvider {
  abstract provider: CloudProvider;
  abstract region: string;

  protected credentials?: ProviderCredentials;
  protected initialized = false;
  protected auditLog: ProviderAuditEntry[] = [];
  protected auditLogPath: string;
  protected credentialManager?: CredentialManager;
  protected readonly DEFAULT_RETRY_CONFIG: RetryConfig = {
    maxAttempts: 3,
    delayMs: 1000,
    backoffMultiplier: 2,
  };

  constructor(auditLogDir?: string) {
    this.auditLogPath = path.join(
      auditLogDir || `.providers_audit/${this.provider}`,
      `${Date.now()}.jsonl`,
    );
  }

  /**
   * Initialize provider with credentials
   */
  async initialize(credentials: ProviderCredentials): Promise<OperationResult<void>> {
    const startTime = Date.now();
    try {
      this.credentials = credentials;
      await this.validateCredentials();
      this.initialized = true;

      await this.logAudit({
        operation: 'initialize',
        success: true,
        message: `Provider ${this.provider} initialized successfully`,
        duration: Date.now() - startTime,
      });

      return { success: true };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.logAudit({
        operation: 'initialize',
        success: false,
        message: `Failed to initialize provider: ${message}`,
        error: message,
        duration: Date.now() - startTime,
      });
      return {
        success: false,
        error: {
          code: 'INIT_FAILED',
          message,
          timestamp: new Date(),
          retryable: true,
        },
      };
    }
  }

  /**
   * Check if provider is initialized
   */
  isInitialized(): boolean {
    return this.initialized && !!this.credentials;
  }

  /**
   * Get credentials
   */
  getCredentials(): ProviderCredentials {
    if (!this.credentials) {
      throw new Error('Provider not initialized');
    }
    return this.credentials;
  }

  /**
   * Validate credentials
   */
  protected abstract validateCredentials(): Promise<void>;

  /**
   * Authenticate with provider
   */
  async authenticate(): Promise<OperationResult<{authenticated: boolean; expiresAt?: Date}>> {
    const startTime = Date.now();
    try {
      if (!this.isInitialized()) {
        throw new Error('Provider not initialized');
      }

      const result = await this.doAuthenticate();

      await this.logAudit({
        operation: 'authenticate',
        success: true,
        message: 'Authentication successful',
        duration: Date.now() - startTime,
      });

      return { success: true, data: result };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.logAudit({
        operation: 'authenticate',
        success: false,
        message: `Authentication failed: ${message}`,
        error: message,
        duration: Date.now() - startTime,
      });
      return {
        success: false,
        error: {
          code: 'AUTH_FAILED',
          message,
          timestamp: new Date(),
          retryable: false,
        },
      };
    }
  }

  protected abstract doAuthenticate(): Promise<{authenticated: boolean; expiresAt?: Date}>;

  /**
   * Refresh credentials
   */
  async refreshCredentials(): Promise<OperationResult<ProviderCredentials>> {
    const startTime = Date.now();
    try {
      if (!this.isInitialized()) {
        throw new Error('Provider not initialized');
      }

      const newCredentials = await this.doRefreshCredentials();
      this.credentials = newCredentials;

      await this.logAudit({
        operation: 'refresh_credentials',
        success: true,
        message: 'Credentials refreshed successfully',
        duration: Date.now() - startTime,
      });

      return { success: true, data: newCredentials };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.logAudit({
        operation: 'refresh_credentials',
        success: false,
        message: `Credential refresh failed: ${message}`,
        error: message,
        duration: Date.now() - startTime,
      });
      return {
        success: false,
        error: {
          code: 'REFRESH_FAILED',
          message,
          timestamp: new Date(),
          retryable: true,
        },
      };
    }
  }

  protected abstract doRefreshCredentials(): Promise<ProviderCredentials>;

  /**
   * Validate credentials
   */
  async validateCredentials(): Promise<OperationResult<{valid: boolean}>> {
    const startTime = Date.now();
    try {
      const valid = await this.doValidateCredentials();
      
      await this.logAudit({
        operation: 'validate_credentials',
        success: valid,
        message: `Credential validation ${valid ? 'passed' : 'failed'}`,
        duration: Date.now() - startTime,
      });

      return { success: true, data: { valid } };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.logAudit({
        operation: 'validate_credentials',
        success: false,
        message: `Credential validation error: ${message}`,
        error: message,
        duration: Date.now() - startTime,
      });
      return {
        success: false,
        error: {
          code: 'VALIDATION_FAILED',
          message,
          timestamp: new Date(),
          retryable: false,
        },
      };
    }
  }

  protected abstract doValidateCredentials(): Promise<boolean>;

  /**
   * Perform operation with retry logic
   */
  protected async withRetry<T>(
    operation: () => Promise<T>,
    config?: Partial<RetryConfig>,
  ): Promise<T> {
    const retryConfig = { ...this.DEFAULT_RETRY_CONFIG, ...config };
    let lastError: Error | null = null;
    let delay = retryConfig.delayMs;

    for (let attempt = 1; attempt <= retryConfig.maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));

        if (attempt < retryConfig.maxAttempts) {
          await this.sleep(delay);
          delay *= retryConfig.backoffMultiplier;
        }
      }
    }

    throw lastError;
  }

  /**
   * Sleep utility
   */
  protected sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Log audit entry
   */
  protected async logAudit(entry: Omit<ProviderAuditEntry, 'timestamp'>): Promise<void> {
    const auditEntry: ProviderAuditEntry = {
      timestamp: new Date(),
      ...entry,
    };

    this.auditLog.push(auditEntry);

    try {
      const logDir = path.dirname(this.auditLogPath);
      await fs.mkdir(logDir, { recursive: true });
      const line = JSON.stringify(auditEntry) + '\n';
      await fs.appendFile(this.auditLogPath, line);
    } catch (error) {
      console.error('Failed to write audit log:', error);
    }
  }

  /**
   * Wrap result with metadata
   */
  protected wrapResult<T>(data: T, requestId?: string): OperationResult<T> {
    return {
      success: true,
      data,
      metadata: {
        executionTime: 0,
        provider: this.provider,
        region: this.region,
        requestId,
      },
    };
  }

  /**
   * Wrap error result
   */
  protected wrapError(code: string, message: string, retryable = true): OperationResult {
    return {
      success: false,
      error: {
        code,
        message,
        timestamp: new Date(),
        retryable,
      },
    };
  }

  /**
   * Health check (must be implemented by subclasses)
   */
  async healthCheck(): Promise<HealthCheckResult> {
    const startTime = Date.now();
    
    try {
      if (!this.isInitialized()) {
        return {
          provider: this.provider,
          healthy: false,
          status: 'unhealthy',
          message: 'Provider not initialized',
          timestamp: new Date(),
          latency: Date.now() - startTime,
        };
      }

      const result = await this.doHealthCheck();
      return {
        provider: this.provider,
        ...result,
        timestamp: new Date(),
        latency: Date.now() - startTime,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return {
        provider: this.provider,
        healthy: false,
        status: 'unhealthy',
        message,
        timestamp: new Date(),
        latency: Date.now() - startTime,
      };
    }
  }

  protected abstract doHealthCheck(): Promise<Omit<HealthCheckResult, 'provider' | 'timestamp' | 'latency'>>;

  /**
   * Get audit log
   */
  getAuditLog(operation?: string): ProviderAuditEntry[] {
    if (!operation) {
      return this.auditLog;
    }
    return this.auditLog.filter(entry => entry.operation === operation);
  }

  /**
   * Get audit log stats
   */
  getAuditStats(): {
    total: number;
    successful: number;
    failed: number;
    byOperation: Record<string, number>;
  } {
    const byOperation: Record<string, number> = {};
    let successful = 0;
    const total = this.auditLog.length;

    this.auditLog.forEach(entry => {
      byOperation[entry.operation] = (byOperation[entry.operation] || 0) + 1;
      if (entry.success) successful++;
    });

    return {
      total,
      successful,
      failed: total - successful,
      byOperation,
    };
  }

  /**
   * Default implementations for resource operations
   */

  async listResources(type: string, filters?: Record<string, any>): Promise<OperationResult<ResourceMetadata[]>> {
    return this.wrapResult([]);
  }

  async getResource(resourceId: string): Promise<OperationResult<ResourceMetadata>> {
    return this.wrapError('NOT_FOUND', `Resource ${resourceId} not found`);
  }

  async createResource(config: Record<string, any>): Promise<OperationResult<ResourceMetadata>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Resource creation not implemented');
  }

  async updateResource(resourceId: string, updates: Record<string, any>): Promise<OperationResult<ResourceMetadata>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Resource update not implemented');
  }

  async deleteResource(resourceId: string): Promise<OperationResult<{deleted: boolean}>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Resource deletion not implemented');
  }

  async provisionCompute(config: ComputeConfig): Promise<OperationResult<ResourceMetadata>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Compute provisioning not implemented');
  }

  async startCompute(resourceId: string): Promise<OperationResult<{started: boolean}>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Start compute not implemented');
  }

  async stopCompute(resourceId: string): Promise<OperationResult<{stopped: boolean}>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Stop compute not implemented');
  }

  async deleteCompute(resourceId: string): Promise<OperationResult<{deleted: boolean}>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Delete compute not implemented');
  }

  async getComputeStatus(resourceId: string): Promise<OperationResult<ComputeStatus>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Get compute status not implemented');
  }

  async createStorage(config: StorageConfig): Promise<OperationResult<ResourceMetadata>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Storage creation not implemented');
  }

  async uploadFile(bucket: string, key: string, data: Buffer | string): Promise<OperationResult<{url: string}>> {
    return this.wrapError('NOT_IMPLEMENTED', 'File upload not implemented');
  }

  async downloadFile(bucket: string, key: string): Promise<OperationResult<Buffer>> {
    return this.wrapError('NOT_IMPLEMENTED', 'File download not implemented');
  }

  async listBucketContents(bucket: string, prefix?: string): Promise<OperationResult<string[]>> {
    return this.wrapError('NOT_IMPLEMENTED', 'List bucket contents not implemented');
  }

  async deleteFile(bucket: string, key: string): Promise<OperationResult<{deleted: boolean}>> {
    return this.wrapError('NOT_IMPLEMENTED', 'File deletion not implemented');
  }

  async createNetwork(config: NetworkConfig): Promise<OperationResult<ResourceMetadata>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Network creation not implemented');
  }

  async createSecurityGroup(config: SecurityGroupConfig): Promise<OperationResult<ResourceMetadata>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Security group creation not implemented');
  }

  async createDatabase(config: DatabaseConfig): Promise<OperationResult<ResourceMetadata>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Database creation not implemented');
  }

  async listRegions(): Promise<OperationResult<RegionInfo[]>> {
    return this.wrapResult([]);
  }

  async getAccountInfo(): Promise<OperationResult<AccountInfo>> {
    return this.wrapError('NOT_IMPLEMENTED', 'Get account info not implemented');
  }

  async listResourceTypes(): Promise<OperationResult<string[]>> {
    return this.wrapResult([]);
  }

  async estimateCosts(resources: ResourceMetadata[]): Promise<OperationResult<{total: number; byResource: Record<string, number>; currency: string}>> {
    return this.wrapResult({ total: 0, byResource: {}, currency: 'USD' });
  }

  async getMetrics(resourceId: string, metricNames: string[]): Promise<OperationResult<MetricData[]>> {
    return this.wrapResult([]);
  }

  async checkRegionAvailability(region: string): Promise<OperationResult<{available: boolean}>> {
    return this.wrapResult({ available: true });
  }

  async checkResourceQuota(resourceType: string): Promise<OperationResult<{available: number; limit: number}>> {
    return this.wrapResult({ available: 100, limit: 100 });
  }

  async cleanup(): Promise<OperationResult<void>> {
    this.initialized = false;
    this.credentials = undefined;
    return { success: true };
  }
}

export { BaseCloudProvider };
