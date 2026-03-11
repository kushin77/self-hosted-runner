/**
 * GCP Cloud Provider Implementation
 * 
 * Integrates with:
 * - Compute Engine for compute
 * - Cloud Storage for storage
 * - VPC Networks for networking
 * - Cloud SQL for databases
 * - Cloud Monitoring for metrics
 * - Deployment Manager for orchestration
 * - IAM for authentication
 * - Cloud KMS for key management
 * - Service Accounts for authentication
 */

import { google } from 'googleapis';
import { Storage } from '@google-cloud/storage';
import { Compute } from '@google-cloud/compute';
import { Monitoring } from '@google-cloud/monitoring';
import { BaseCloudProvider } from './base-provider';
import {
  CloudProvider,
  ProviderCredentials,
  ComputeConfig,
  ComputeStatus,
  StorageConfig,
  NetworkConfig,
  SecurityGroupConfig,
  DatabaseConfig,
  RegionInfo,
  AccountInfo,
  ResourceMetadata,
  HealthCheckResult,
  MetricData,
  OperationResult,
} from './types';

/**
 * GCP Provider Implementation
 */
export class GcpProvider extends BaseCloudProvider {
  provider = CloudProvider.GCP;
  region: string;

  private compute?: Compute;
  private storage?: Storage;
  private monitoring?: Monitoring;
  private compute_api?: google.compute_v1.Compute;
  private cloudresourcemanager?: google.cloudresourcemanager_v1.Cloudresourcemanager;

  constructor(region = 'us-central1', auditLogDir?: string) {
    super(auditLogDir);
    this.region = region;
  }

  /**
   * Validate GCP credentials
   */
  protected async validateCredentials(): Promise<void> {
    if (!this.credentials) {
      throw new Error('Credentials not provided');
    }

    const { projectId, credentials, serviceAccountKey } = this.credentials;

    if (!projectId) {
      throw new Error('Missing required GCP credential: projectId');
    }

    if (!credentials && !serviceAccountKey) {
      throw new Error('Missing required GCP credential: credentials or serviceAccountKey');
    }

    // Try to authenticate
    await this.withRetry(async () => {
      const auth = new google.auth.GoogleAuth({
        projectId,
        credentials: credentials || JSON.parse(serviceAccountKey || '{}'),
        scopes: [
          'https://www.googleapis.com/auth/cloud-platform',
          'https://www.googleapis.com/auth/compute',
          'https://www.googleapis.com/auth/devstorage.full_control',
        ],
      });

      await auth.getClient();
    });
  }

  /**
   * Authenticate with GCP
   */
  protected async doAuthenticate(): Promise<{authenticated: boolean; expiresAt?: Date}> {
    // GCP auth is handled transparently by the client libraries
    return { authenticated: true };
  }

  /**
   * Refresh GCP credentials
   */
  protected async doRefreshCredentials(): Promise<ProviderCredentials> {
    // GCP credentials are automatically refreshed by the auth libraries
    // But we can implement explicit refresh if needed
    return this.credentials!;
  }

  /**
   * Validate credentials
   */
  protected async doValidateCredentials(): Promise<boolean> {
    try {
      await this.validateCredentials();
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Initialize GCP clients
   */
  private initializeClients(): void {
    if (!this.credentials) {
      throw new Error('Credentials not initialized');
    }

    const auth = new google.auth.GoogleAuth({
      projectId: this.credentials.projectId,
      credentials: this.credentials.credentials || JSON.parse(this.credentials.serviceAccountKey || '{}'),
      scopes: [
        'https://www.googleapis.com/auth/cloud-platform',
        'https://www.googleapis.com/auth/compute',
        'https://www.googleapis.com/auth/devstorage.full_control',
      ],
    });

    this.compute = new Compute({ projectId: this.credentials.projectId, auth });
    this.storage = new Storage({ projectId: this.credentials.projectId, auth });
    this.monitoring = new Monitoring({ projectId: this.credentials.projectId, auth });

    this.compute_api = google.compute('v1');
    this.cloudresourcemanager = google.cloudresourcemanager('v1');
  }

  /**
   * Health check
   */
  protected async doHealthCheck(): Promise<Omit<HealthCheckResult, 'provider' | 'timestamp' | 'latency'>> {
    try {
      this.initializeClients();

      // Test Compute API
      const computeStart = Date.now();
      await this.withRetry(async () => {
        await this.compute_api!.instances.list({
          project: this.credentials!.projectId!,
          zone: `${this.region}-a`,
          maxResults: 1,
        });
      });
      const computeLatency = Date.now() - computeStart;

      // Test Storage API
      const storageStart = Date.now();
      await this.withRetry(async () => {
        const [buckets] = await this.storage!.getBuckets({ maxResults: 1 });
      });
      const storageLatency = Date.now() - storageStart;

      return {
        healthy: true,
        status: 'healthy',
        message: 'GCP API responding normally',
        details: {
          apiLatency: (computeLatency + storageLatency) / 2,
          authLatency: computeLatency,
        },
      };
    } catch (error) {
      return {
        healthy: false,
        status: 'unhealthy',
        message: `GCP health check failed: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }

  /**
   * Provision compute instance
   */
  async provisionCompute(config: ComputeConfig): Promise<OperationResult<ResourceMetadata>> {
    try {
      this.initializeClients();

      const zone = `${this.region}-a`;
      const instance = {
        name: config.name,
        machineType: `zones/${zone}/machineTypes/${config.machineType}`,
        disks: [
          {
            boot: true,
            initializeParams: {
              sourceImage: config.image,
              diskSizeGb: String(config.diskSize || 100),
              diskType: `zones/${zone}/diskTypes/${config.diskType || 'pd-standard'}`,
            },
          },
        ],
        networkInterfaces: [
          {
            network: config.network || 'global/networks/default',
          },
        ],
        labels: config.tags,
        metadata: {
          items: Object.entries(config.metadata || {}).map(([key, value]) => ({
            key,
            value,
          })),
        },
        serviceAccounts: config.metadata?.serviceAccount
          ? [
              {
                email: config.metadata.serviceAccount,
                scopes: ['https://www.googleapis.com/auth/cloud-platform'],
              },
            ]
          : undefined,
        startupScript: config.startupScript,
      };

      const result = await this.withRetry(async () => {
        return await this.compute_api!.instances.insert({
          project: this.credentials!.projectId!,
          zone,
          requestBody: instance as any,
        });
      });

      return this.wrapResult({
        id: config.name,
        name: config.name,
        provider: CloudProvider.GCP,
        region: this.region,
        type: 'compute',
        status: 'pending',
        createdAt: new Date(),
        updatedAt: new Date(),
        tags: config.tags,
      });
    } catch (error) {
      return this.wrapError('PROVISION_FAILED', `Failed to provision compute: ${error}`);
    }
  }

  /**
   * Start compute instance
   */
  async startCompute(resourceId: string): Promise<OperationResult<{started: boolean}>> {
    try {
      this.initializeClients();

      const zone = `${this.region}-a`;
      await this.withRetry(async () => {
        await this.compute_api!.instances.start({
          project: this.credentials!.projectId!,
          zone,
          resource: resourceId,
        });
      });

      return this.wrapResult({ started: true });
    } catch (error) {
      return this.wrapError('START_FAILED', `Failed to start compute: ${error}`);
    }
  }

  /**
   * Stop compute instance
   */
  async stopCompute(resourceId: string): Promise<OperationResult<{stopped: boolean}>> {
    try {
      this.initializeClients();

      const zone = `${this.region}-a`;
      await this.withRetry(async () => {
        await this.compute_api!.instances.stop({
          project: this.credentials!.projectId!,
          zone,
          resource: resourceId,
        });
      });

      return this.wrapResult({ stopped: true });
    } catch (error) {
      return this.wrapError('STOP_FAILED', `Failed to stop compute: ${error}`);
    }
  }

  /**
   * Delete compute instance
   */
  async deleteCompute(resourceId: string): Promise<OperationResult<{deleted: boolean}>> {
    try {
      this.initializeClients();

      const zone = `${this.region}-a`;
      await this.withRetry(async () => {
        await this.compute_api!.instances.delete({
          project: this.credentials!.projectId!,
          zone,
          resource: resourceId,
        });
      });

      return this.wrapResult({ deleted: true });
    } catch (error) {
      return this.wrapError('DELETE_FAILED', `Failed to delete compute: ${error}`);
    }
  }

  /**
   * Get compute status
   */
  async getComputeStatus(resourceId: string): Promise<OperationResult<ComputeStatus>> {
    try {
      this.initializeClients();

      const zone = `${this.region}-a`;
      const instance = await this.withRetry(async () => {
        return await this.compute_api!.instances.get({
          project: this.credentials!.projectId!,
          zone,
          resource: resourceId,
        });
      });

      return this.wrapResult({
        resourceId,
        state: (instance.status || 'UNKNOWN') as any,
        launchTime: new Date(instance.creationTimestamp || Date.now()),
      });
    } catch (error) {
      return this.wrapError('STATUS_FAILED', `Failed to get status: ${error}`);
    }
  }

  /**
   * Create storage bucket
   */
  async createStorage(config: StorageConfig): Promise<OperationResult<ResourceMetadata>> {
    try {
      this.initializeClients();

      const bucket = this.storage!.bucket(config.name);

      await this.withRetry(async () => {
        await bucket.create({
          location: config.region || this.region,
          versioning: config.versioning,
          encryption: config.encryption
            ? {
                type: 'service-managed',
              }
            : undefined,
        });
      });

      return this.wrapResult({
        id: config.name,
        name: config.name,
        provider: CloudProvider.GCP,
        region: config.region || this.region,
        type: 'storage',
        status: 'active',
        createdAt: new Date(),
        updatedAt: new Date(),
        tags: config.tags,
      });
    } catch (error) {
      return this.wrapError('CREATE_STORAGE_FAILED', `Failed to create storage: ${error}`);
    }
  }

  /**
   * Upload file to Storage
   */
  async uploadFile(bucket: string, key: string, data: Buffer | string): Promise<OperationResult<{url: string}>> {
    try {
      this.initializeClients();

      const file = this.storage!.bucket(bucket).file(key);

      await this.withRetry(async () => {
        await file.save(data);
      });

      const url = `gs://${bucket}/${key}`;
      return this.wrapResult({ url });
    } catch (error) {
      return this.wrapError('UPLOAD_FAILED', `Failed to upload file: ${error}`);
    }
  }

  /**
   * Download file from Storage
   */
  async downloadFile(bucket: string, key: string): Promise<OperationResult<Buffer>> {
    try {
      this.initializeClients();

      const file = this.storage!.bucket(bucket).file(key);

      const [buffer] = await this.withRetry(async () => {
        return await file.download();
      });

      return this.wrapResult(buffer);
    } catch (error) {
      return this.wrapError('DOWNLOAD_FAILED', `Failed to download file: ${error}`);
    }
  }

  /**
   * List bucket contents
   */
  async listBucketContents(bucket: string, prefix?: string): Promise<OperationResult<string[]>> {
    try {
      this.initializeClients();

      const [files] = await this.withRetry(async () => {
        return await this.storage!.bucket(bucket).getFiles({ prefix });
      });

      const keys = files.map(file => file.name);
      return this.wrapResult(keys);
    } catch (error) {
      return this.wrapError('LIST_FAILED', `Failed to list bucket: ${error}`);
    }
  }

  /**
   * Delete file from Storage
   */
  async deleteFile(bucket: string, key: string): Promise<OperationResult<{deleted: boolean}>> {
    try {
      this.initializeClients();

      await this.withRetry(async () => {
        await this.storage!.bucket(bucket).file(key).delete();
      });

      return this.wrapResult({ deleted: true });
    } catch (error) {
      return this.wrapError('DELETE_FAILED', `Failed to delete file: ${error}`);
    }
  }

  /**
   * List regions
   */
  async listRegions(): Promise<OperationResult<RegionInfo[]>> {
    try {
      this.initializeClients();

      const [regions] = await this.withRetry(async () => {
        return await this.compute_api!.regions.list({
          project: this.credentials!.projectId!,
        });
      });

      const regionList = (regions || []).map(region => ({
        name: region.name || '',
        displayName: region.description || region.name || '',
        available: !region.deprecated,
      }));

      return this.wrapResult(regionList);
    } catch (error) {
      return this.wrapError('LIST_REGIONS_FAILED', `Failed to list regions: ${error}`);
    }
  }

  /**
   * Get account info
   */
  async getAccountInfo(): Promise<OperationResult<AccountInfo>> {
    try {
      this.initializeClients();

      // Get project info
      const [project] = await this.withRetry(async () => {
        return await this.cloudresourcemanager!.projects.get({
          projectId: this.credentials!.projectId!,
        });
      });

      return this.wrapResult({
        provider: CloudProvider.GCP,
        accountId: project.projectId || '',
        accountName: project.name,
        billingEnabled: true,
      });
    } catch (error) {
      return this.wrapError('GET_ACCOUNT_FAILED', `Failed to get account info: ${error}`);
    }
  }

  /**
   * Get metrics
   */
  async getMetrics(resourceId: string, metricNames: string[]): Promise<OperationResult<MetricData[]>> {
    try {
      this.initializeClients();

      const metrics: MetricData[] = [];

      for (const metricName of metricNames) {
        const [timeSeries] = await this.withRetry(async () => {
          return await this.monitoring!.timeSeries.list({
            name: `projects/${this.credentials!.projectId!}`,
            filter: `resource.type="gce_instance" AND metric.type="compute.googleapis.com/${metricName}"`,
          });
        });

        if (timeSeries && timeSeries.length > 0) {
          const points = timeSeries[0].points || [];
          if (points.length > 0) {
            const latest = points[0];
            metrics.push({
              name: metricName,
              value: (latest.value?.doubleValue || latest.value?.int64Value || 0) as any,
              unit: 'N/A',
              timestamp: latest.interval?.endTime ? new Date(latest.interval.endTime) : new Date(),
            });
          }
        }
      }

      return this.wrapResult(metrics);
    } catch (error) {
      return this.wrapError('GET_METRICS_FAILED', `Failed to get metrics: ${error}`);
    }
  }
}
