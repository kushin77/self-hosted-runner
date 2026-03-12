/**
 * AWS Cloud Provider Implementation
 * 
 * Integrates with:
 * - EC2 for compute
 * - S3 for storage
 * - VPC for networking
 * - RDS for databases
 * - CloudWatch for metrics
 * - CloudFormation for orchestration
 * - IAM for authentication
 * - KMS for credential encryption
 * - Assume Role for cross-account operations
 */

import * as AWS from 'aws-sdk';
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
 * AWS Provider Implementation
 */
export class AwsProvider extends BaseCloudProvider {
  provider = CloudProvider.AWS;
  region: string;

  private ec2?: AWS.EC2;
  private s3?: AWS.S3;
  private rds?: AWS.RDS;
  private cloudwatch?: AWS.CloudWatch;
  private iam?: AWS.IAM;
  private sts?: AWS.STS;
  private cloudformation?: AWS.CloudFormation;

  constructor(region = 'us-east-1', auditLogDir?: string) {
    super(auditLogDir);
    this.region = region;
  }

  /**
   * Provider-local credential checks (internal helper)
   */
  private async checkCredentials(): Promise<void> {
    if (!this.credentials) {
      throw new Error('Credentials not provided');
    }

    const { accessKeyId, secretAccessKey, region } = this.credentials;

    if (!accessKeyId || !secretAccessKey || !region) {
      throw new Error('Missing required AWS credentials: accessKeyId, secretAccessKey, region');
    }

    // Test credentials by making a simple API call
    await this.withRetry(async () => {
      const sts = new AWS.STS({
        accessKeyId: accessKeyId,
        secretAccessKey,
        region,
      });

      await sts.getCallerIdentity({}).promise();
    });
  }

  /**
   * Authenticate with AWS
   */
  protected async doAuthenticate(): Promise<{authenticated: boolean; expiresAt?: Date}> {
    // Check if temp credentials need refresh
    if (this.credentials?.sessionToken && this.credentials?.expiresAt) {
      const expiresAt = new Date(this.credentials.expiresAt);
      const now = new Date();
      
      if (expiresAt <= now) {
        throw new Error('AWS credentials expired');
      }
    }

    return { authenticated: true };
  }

  /**
   * Refresh AWS credentials
   */
  protected async doRefreshCredentials(): Promise<ProviderCredentials> {
    if (!this.credentials?.assumeRoleArn) {
      throw new Error('Cannot refresh credentials without assumeRoleArn');
    }

    const refreshedCreds = await this.withRetry(async () => {
      const sts = new AWS.STS({
        accessKeyId: this.credentials!.accessKeyId,
        secretAccessKey: this.credentials!.secretAccessKey,
        region: this.region,
      });

      const response = await sts
        .assumeRole({
          RoleArn: this.credentials!.assumeRoleArn!,
          RoleSessionName: this.credentials!.assumeRoleSessionName || 'nexus-shield-sync',
          DurationSeconds: 3600,
          ExternalId: this.credentials!.externalId,
          SerialNumber: this.credentials!.mfaSerial,
          TokenCode: this.credentials!.mfaToken,
        })
        .promise();

      return response;
    });

    return {
      ...this.credentials,
      accessKeyId: refreshedCreds.Credentials!.AccessKeyId,
      secretAccessKey: refreshedCreds.Credentials!.SecretAccessKey,
      sessionToken: refreshedCreds.Credentials!.SessionToken,
      expiresAt: refreshedCreds.Credentials!.Expiration,
    };
  }

  /**
   * Validate credentials
   */
  protected async doValidateCredentials(): Promise<boolean> {
    try {
      await this.checkCredentials();
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Initialize AWS clients
   */
  private initializeClients(): void {
    if (!this.credentials) {
      throw new Error('Credentials not initialized');
    }

    const config = {
      accessKeyId: this.credentials.accessKeyId,
      secretAccessKey: this.credentials.secretAccessKey,
      sessionToken: this.credentials.sessionToken,
      region: this.region,
    };

    this.ec2 = new AWS.EC2(config);
    this.s3 = new AWS.S3(config);
    this.rds = new AWS.RDS(config);
    this.cloudwatch = new AWS.CloudWatch(config);
    this.iam = new AWS.IAM(config);
    this.sts = new AWS.STS(config);
    this.cloudformation = new AWS.CloudFormation(config);
  }

  /**
   * Health check
   */
  protected async doHealthCheck(): Promise<Omit<HealthCheckResult, 'provider' | 'timestamp' | 'latency'>> {
    try {
      this.initializeClients();

      // Test EC2 API
      const ec2Start = Date.now();
      await this.ec2!.describeInstances({ MaxResults: 1 }).promise();
      const ec2Latency = Date.now() - ec2Start;

      // Test S3
      const s3Start = Date.now();
      await this.s3!.listBuckets().promise();
      const s3Latency = Date.now() - s3Start;

      return {
        healthy: true,
        status: 'healthy',
        message: 'AWS API responding normally',
        details: {
          apiLatency: (ec2Latency + s3Latency) / 2,
          authLatency: ec2Latency,
        },
      };
    } catch (error) {
      return {
        healthy: false,
        status: 'unhealthy',
        message: `AWS health check failed: ${error instanceof Error ? error.message : String(error)}`,
      };
    }
  }

  /**
   * Provision compute instance
   */
  async provisionCompute(config: ComputeConfig): Promise<OperationResult<ResourceMetadata>> {
    try {
      this.initializeClients();

      const result = await this.withRetry(async () => {
        return await this.ec2!
          .runInstances({
            ImageId: config.image,
            MinCount: 1,
            MaxCount: 1,
            InstanceType: config.machineType as any,
            SubnetId: config.network,
            SecurityGroupIds: config.securityGroup ? [config.securityGroup] : undefined,
            TagSpecifications: [
              {
                ResourceType: 'instance',
                Tags: Object.entries(config.tags || {}).map(([Key, Value]) => ({ Key, Value })),
              },
            ],
            UserData: config.startupScript
              ? Buffer.from(config.startupScript).toString('base64')
              : undefined,
            IamInstanceProfile: config.instanceProfile ? { Arn: config.instanceProfile } : undefined,
            BlockDeviceMappings: config.diskSize
              ? [
                  {
                    DeviceName: '/dev/xvda',
                    Ebs: {
                      VolumeSize: config.diskSize,
                      VolumeType: (config.diskType || 'gp3') as any,
                      DeleteOnTermination: true,
                    },
                  },
                ]
              : undefined,
          })
          .promise();
      });

      const instance = result.Instances![0];

      return this.wrapResult({
        id: instance.InstanceId!,
        name: config.name,
        provider: CloudProvider.AWS,
        region: this.region,
        type: 'compute',
        status: 'pending',
        createdAt: instance.LaunchTime || new Date(),
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

      await this.withRetry(async () => {
        await this.ec2!.startInstances({ InstanceIds: [resourceId] }).promise();
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

      await this.withRetry(async () => {
        await this.ec2!.stopInstances({ InstanceIds: [resourceId] }).promise();
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

      await this.withRetry(async () => {
        await this.ec2!.terminateInstances({ InstanceIds: [resourceId] }).promise();
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

      const result = await this.withRetry(async () => {
        return await this.ec2!.describeInstances({ InstanceIds: [resourceId] }).promise();
      });

      const instance = result.Reservations![0]?.Instances![0];

      if (!instance) {
        return this.wrapError('NOT_FOUND', 'Instance not found');
      }

      return this.wrapResult({
        resourceId,
        state: (instance.State?.Name || 'unknown') as any,
        publicIp: instance.PublicIpAddress,
        privateIp: instance.PrivateIpAddress,
        launchTime: instance.LaunchTime,
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

      await this.withRetry(async () => {
        await this.s3!
          .createBucket({
            Bucket: config.name,
            CreateBucketConfiguration:
              this.region !== 'us-east-1' ? { LocationConstraint: this.region as any } : undefined,
          })
          .promise();

        if (config.versioning) {
          await this.s3!
            .putBucketVersioning({
              Bucket: config.name,
              VersioningConfiguration: { Status: 'Enabled' },
            })
            .promise();
        }

        if (config.encryption) {
          await this.s3!
            .putBucketEncryption({
              Bucket: config.name,
              ServerSideEncryptionConfiguration: {
                Rules: [
                  {
                    ApplyServerSideEncryptionByDefault: {
                      SSEAlgorithm: 'AES256',
                    },
                  },
                ],
              },
            })
            .promise();
        }
      });

      return this.wrapResult({
        id: config.name,
        name: config.name,
        provider: CloudProvider.AWS,
        region: this.region,
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
   * Upload file to S3
   */
  async uploadFile(bucket: string, key: string, data: Buffer | string): Promise<OperationResult<{url: string}>> {
    try {
      this.initializeClients();

      await this.withRetry(async () => {
        await this.s3!
          .putObject({
            Bucket: bucket,
            Key: key,
            Body: data,
          })
          .promise();
      });

      const url = `s3://${bucket}/${key}`;
      return this.wrapResult({ url });
    } catch (error) {
      return this.wrapError('UPLOAD_FAILED', `Failed to upload file: ${error}`);
    }
  }

  /**
   * Download file from S3
   */
  async downloadFile(bucket: string, key: string): Promise<OperationResult<Buffer>> {
    try {
      this.initializeClients();

      const result = await this.withRetry(async () => {
        return await this.s3!
          .getObject({
            Bucket: bucket,
            Key: key,
          })
          .promise();
      });

      return this.wrapResult(result.Body as Buffer);
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

      const result = await this.withRetry(async () => {
        return await this.s3!
          .listObjectsV2({
            Bucket: bucket,
            Prefix: prefix,
          })
          .promise();
      });

      const keys = (result.Contents || []).map(obj => obj.Key!);
      return this.wrapResult(keys);
    } catch (error) {
      return this.wrapError('LIST_FAILED', `Failed to list bucket: ${error}`);
    }
  }

  /**
   * Delete file from S3
   */
  async deleteFile(bucket: string, key: string): Promise<OperationResult<{deleted: boolean}>> {
    try {
      this.initializeClients();

      await this.withRetry(async () => {
        await this.s3!
          .deleteObject({
            Bucket: bucket,
            Key: key,
          })
          .promise();
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

      const result = await this.withRetry(async () => {
        const ec2 = new AWS.EC2({ region: 'us-east-1' }); // Regions API available in us-east-1
        return await ec2.describeRegions().promise();
      });

      const regions = (result.Regions || []).map(r => ({
        name: r.RegionName!,
        displayName: r.RegionName!,
        available: r.OptInStatus !== 'opted-out',
      }));

      return this.wrapResult(regions);
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

      const identity = await this.withRetry(async () => {
        return await this.sts!.getCallerIdentity().promise();
      });

      return this.wrapResult({
        provider: CloudProvider.AWS,
        accountId: identity.Account!,
        email: undefined, // AWS doesn't provide email in getCallerIdentity
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
        const result = await this.withRetry(async () => {
          return await this.cloudwatch!
            .getMetricStatistics({
              Namespace: 'AWS/EC2',
              MetricName: metricName,
              Dimensions: [
                {
                  Name: 'InstanceId',
                  Value: resourceId,
                },
              ],
              StartTime: new Date(Date.now() - 3600 * 1000),
              EndTime: new Date(),
              Period: 300,
              Statistics: ['Average'],
            })
            .promise();
        });

        if (result.Datapoints && result.Datapoints.length > 0) {
          const latest = result.Datapoints.sort((a, b) => {
            const aTime = a.Timestamp?.getTime() || 0;
            const bTime = b.Timestamp?.getTime() || 0;
            return bTime - aTime;
          })[0];

          metrics.push({
            name: metricName,
            value: latest.Average || 0,
            unit: 'Percent',
            timestamp: latest.Timestamp || new Date(),
          });
        }
      }

      return this.wrapResult(metrics);
    } catch (error) {
      return this.wrapError('GET_METRICS_FAILED', `Failed to get metrics: ${error}`);
    }
  }
}
