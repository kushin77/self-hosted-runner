/**
 * Cloud Provider Registry & Factory
 * 
 * Centralized provider management:
 * - Registration and lookup
 * - Initialization and cleanup
 * - Health monitoring
 * - Multi-cloud operations
 */

import { CloudProvider, ICloudProvider, ProviderRegistry } from './types';
import { AwsProvider } from './aws-provider';
import { GcpProvider } from './gcp-provider';
import { AzureProvider } from './azure-provider';
import * as fs from 'fs/promises';
import * as path from 'path';

/**
 * Default provider registry implementation
 */
export class DefaultProviderRegistry implements ProviderRegistry {
  private providers = new Map<CloudProvider, ICloudProvider>();
  private auditLogPath: string;
  private auditLog: any[] = [];

  constructor(auditLogDir?: string) {
    this.auditLogPath = path.join(auditLogDir || '.providers_registry', `${Date.now()}.jsonl`);
  }

  /**
   * Register a provider
   */
  register(provider: CloudProvider, instance: ICloudProvider): void {
    if (this.providers.has(provider)) {
      console.warn(`Provider ${provider} is already registered, overwriting...`);
    }

    this.providers.set(provider, instance);
    this.logAudit({
      operation: 'register',
      provider,
      success: true,
      message: `Registered provider ${provider}`,
    });
  }

  /**
   * Get provider by type
   */
  get(provider: CloudProvider): ICloudProvider | null {
    return this.providers.get(provider) || null;
  }

  /**
   * Get all providers
   */
  getAll(): ICloudProvider[] {
    return Array.from(this.providers.values());
  }

  /**
   * Check if provider is registered
   */
  has(provider: CloudProvider): boolean {
    return this.providers.has(provider);
  }

  /**
   * Unregister a provider
   */
  unregister(provider: CloudProvider): boolean {
    const result = this.providers.delete(provider);
    
    if (result) {
      this.logAudit({
        operation: 'unregister',
        provider,
        success: true,
        message: `Unregistered provider ${provider}`,
      });
    }

    return result;
  }

  /**
   * Log audit entry
   */
  private async logAudit(entry: Record<string, any>): Promise<void> {
    const auditEntry = {
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
   * Get audit log
   */
  getAuditLog(): any[] {
    return this.auditLog;
  }
}

/**
 * Provider factory - creates instances with common configuration
 */
export class ProviderFactory {
  private static registry: ProviderRegistry | null = null;

  /**
   * Initialize default registry with all providers
   */
  static initializeDefaultRegistry(auditLogDir?: string): ProviderRegistry {
    const registry = new DefaultProviderRegistry(auditLogDir);

    // Register default providers
    registry.register(CloudProvider.AWS, new AwsProvider('us-east-1', auditLogDir));
    registry.register(CloudProvider.GCP, new GcpProvider('us-central1', auditLogDir));
    registry.register(CloudProvider.AZURE, new AzureProvider('eastus', auditLogDir));

    this.registry = registry;
    return registry;
  }

  /**
   * Get or create default registry
   */
  static getRegistry(auditLogDir?: string): ProviderRegistry {
    if (!this.registry) {
      this.initializeDefaultRegistry(auditLogDir);
    }
    return this.registry!;
  }

  /**
   * Create provider instance
   */
  static create(provider: CloudProvider, region?: string, auditLogDir?: string): ICloudProvider {
    switch (provider) {
      case CloudProvider.AWS:
        return new AwsProvider(region || 'us-east-1', auditLogDir);
      case CloudProvider.GCP:
        return new GcpProvider(region || 'us-central1', auditLogDir);
      case CloudProvider.AZURE:
        return new AzureProvider(region || 'eastus', auditLogDir);
      default:
        throw new Error(`Unknown provider: ${provider}`);
    }
  }

  /**
   * Create multiple providers
   */
  static createMultiple(
    providers: CloudProvider[],
    region?: string,
    auditLogDir?: string,
  ): ICloudProvider[] {
    return providers.map(p => this.create(p, region, auditLogDir));
  }

  /**
   * Create registry with specific providers
   */
  static createRegistry(
    providers: CloudProvider[],
    region?: string,
    auditLogDir?: string,
  ): ProviderRegistry {
    const registry = new DefaultProviderRegistry(auditLogDir);

    for (const provider of providers) {
      const instance = this.create(provider, region, auditLogDir);
      registry.register(provider, instance);
    }

    return registry;
  }
}

/**
 * Multi-cloud provider manager
 */
export class MultiCloudProviderManager {
  private registry: ProviderRegistry;
  private initialized = new Map<CloudProvider, boolean>();

  constructor(registry?: ProviderRegistry) {
    this.registry = registry || ProviderFactory.getRegistry();
  }

  /**
   * Initialize all providers
   */
  async initializeAll(credentialsMap: Map<CloudProvider, any>): Promise<{
    successful: CloudProvider[];
    failed: Array<{provider: CloudProvider; error: string}>;
  }> {
    const successful: CloudProvider[] = [];
    const failed: Array<{provider: CloudProvider; error: string}> = [];

    for (const provider of Object.values(CloudProvider)) {
      const credentials = credentialsMap.get(provider as CloudProvider);

      if (!credentials) {
        continue;
      }

      try {
        const instance = this.registry.get(provider as CloudProvider);
        if (!instance) {
          throw new Error(`Provider ${provider} not registered`);
        }

        const result = await instance.initialize(credentials);
        if (result.success) {
          this.initialized.set(provider as CloudProvider, true);
          successful.push(provider as CloudProvider);
        } else {
          failed.push({
            provider: provider as CloudProvider,
            error: result.error?.message || 'Unknown error',
          });
        }
      } catch (error) {
        failed.push({
          provider: provider as CloudProvider,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    return { successful, failed };
  }

  /**
   * Get initialized providers
   */
  getInitializedProviders(): ICloudProvider[] {
    return Array.from(this.initialized.entries())
      .filter(([, initialized]) => initialized)
      .map(([provider, ]) => this.registry.get(provider)!)
      .filter((p): p is ICloudProvider => p !== null);
  }

  /**
   * Check if provider is initialized
   */
  isInitialized(provider: CloudProvider): boolean {
    return this.initialized.get(provider) || false;
  }

  /**
   * Get provider
   */
  getProvider(provider: CloudProvider): ICloudProvider | null {
    return this.registry.get(provider);
  }

  /**
   * Get provider registry
   */
  getRegistry(): ProviderRegistry {
    return this.registry;
  }

  /**
   * Health check all
   */
  async healthCheckAll(): Promise<{provider: CloudProvider; healthy: boolean; message: string}[]> {
    const results = [];

    for (const provider of this.getInitializedProviders()) {
      const result = await provider.healthCheck();
      results.push({
        provider: result.provider,
        healthy: result.healthy,
        message: result.message,
      });
    }

    return results;
  }

  /**
   * Cleanup all
   */
  async cleanupAll(): Promise<void> {
    for (const provider of this.getInitializedProviders()) {
      try {
        await provider.cleanup();
      } catch (error) {
        console.error(`Error cleaning up ${provider.provider}:`, error);
      }
    }

    this.initialized.clear();
  }
}

export {
  ProviderRegistry,
};
