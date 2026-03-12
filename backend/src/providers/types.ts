/**
 * Multi-Cloud Provider Types & Interfaces
 * 
 * Defines the core provider contract for cloud-agnostic operations:
 * - Authentication and credential management
 * - Resource provisioning (compute, storage, networking)
 * - Health monitoring
 * - Metadata and discovery
 * - Cost tracking
 * 
 * All providers implement this interface for interchangeability.
 */

/**
 * Cloud provider enumeration
 */
export enum CloudProvider {
  AWS = 'aws',
  GCP = 'gcp',
  AZURE = 'azure',
}

/**
 * Credential types for each provider
 */
export interface ProviderCredentials {
  provider: CloudProvider;
  accessKeyId?: string;      // AWS
  secretAccessKey?: string;  // AWS
  region?: string;           // AWS, etc.
  projectId?: string;        // GCP
  serviceAccountKey?: string; // GCP
  credentials?: Record<string, any>; // GCP parsed JSON
  tenantId?: string;         // Azure
  clientId?: string;         // Azure
  clientSecret?: string;     // Azure
  subscriptionId?: string;   // Azure
  apiKey?: string;          // Generic backup
  assumeRoleArn?: string;    // AWS cross-account
  assumeRoleSessionName?: string; // AWS assume role
  externalId?: string;      // AWS assume role external ID
  mfaSerial?: string;       // AWS MFA
  mfaToken?: string;        // AWS MFA token
  sessionToken?: string;    // AWS temporary session
  expiresAt?: Date;         // AWS temporary credential expiry
  tags?: Record<string, string>; // Resource tags
  metadata?: Record<string, any>; // Provider-specific metadata
}

/**
 * Credential source configuration
 */
export interface CredentialSource {
  type: 'gsm' | 'vault' | 'kms' | 'file';
  location: string;  // e.g., 'projects/my-project/secrets/aws-creds/versions/latest'
  provider: CloudProvider;
  priority: number;  // Lower = higher priority
  fallthrough?: boolean; // Move to next on failure
}

/**
 * Health check result
 */
export interface HealthCheckResult {
  provider: CloudProvider;
  healthy: boolean;
  status: 'healthy' | 'degraded' | 'unhealthy' | 'unknown';
  message: string;
  timestamp: Date;
  latency: number; // milliseconds
  region?: string;
  details?: {
    apiLatency?: number;
    authLatency?: number;
    availableResources?: number;
    errorCount?: number;
    lastSuccess?: Date;
  };
}

/**
 * Resource metadata
 */
export interface ResourceMetadata {
  id: string;
  name: string;
  provider: CloudProvider;
  region: string;
  type: string; // compute | storage | network | database | etc.
  status: 'active' | 'inactive' | 'pending' | 'failed' | 'unknown';
  createdAt: Date;
  updatedAt: Date;
  tags?: Record<string, string>;
  costs?: {
    estimatedHourly: number;
    estimatedMonthly: number;
    currency: string;
  };
  metadata?: Record<string, any>;
}

/**
 * Provider operation result
 */
export interface OperationResult<T = any> {
  success: boolean;
  data?: T;
  error?: {
    code: string;
    message: string;
    details?: Record<string, any>;
    timestamp: Date;
    retryable: boolean;
  };
  metadata?: {
    executionTime: number;
    requestId?: string;
    provider: CloudProvider;
    region?: string;
  };
}

/**
 * Cloud provider interface - all providers implement this
 */
export interface ICloudProvider {
  provider: CloudProvider;
  region: string;
  
  // Initialization
  initialize(credentials: ProviderCredentials): Promise<OperationResult<void>>;
  isInitialized(): boolean;
  getCredentials(): ProviderCredentials;
  
  // Authentication
  authenticate(): Promise<OperationResult<{authenticated: boolean; expiresAt?: Date}>>;
  refreshCredentials(): Promise<OperationResult<ProviderCredentials>>;
  validateCredentials(): Promise<OperationResult<{valid: boolean}>>;
  
  // Health checks
  healthCheck(): Promise<HealthCheckResult>;
  checkRegionAvailability(region: string): Promise<OperationResult<{available: boolean}>>;
  checkResourceQuota(resourceType: string): Promise<OperationResult<{available: number; limit: number}>>;
  
  // Resource operations
  listResources(type: string, filters?: Record<string, any>): Promise<OperationResult<ResourceMetadata[]>>;
  getResource(resourceId: string): Promise<OperationResult<ResourceMetadata>>;
  createResource(config: Record<string, any>): Promise<OperationResult<ResourceMetadata>>;
  updateResource(resourceId: string, updates: Record<string, any>): Promise<OperationResult<ResourceMetadata>>;
  deleteResource(resourceId: string): Promise<OperationResult<{deleted: boolean}>>;
  
  // Compute (VM/Container)
  provisionCompute(config: ComputeConfig): Promise<OperationResult<ResourceMetadata>>;
  startCompute(resourceId: string): Promise<OperationResult<{started: boolean}>>;
  stopCompute(resourceId: string): Promise<OperationResult<{stopped: boolean}>>;
  deleteCompute(resourceId: string): Promise<OperationResult<{deleted: boolean}>>;
  getComputeStatus(resourceId: string): Promise<OperationResult<ComputeStatus>>;
  
  // Storage (Object/Blob)
  createStorage(config: StorageConfig): Promise<OperationResult<ResourceMetadata>>;
  uploadFile(bucket: string, key: string, data: Buffer | string): Promise<OperationResult<{url: string}>>;
  downloadFile(bucket: string, key: string): Promise<OperationResult<Buffer>>;
  listBucketContents(bucket: string, prefix?: string): Promise<OperationResult<string[]>>;
  deleteFile(bucket: string, key: string): Promise<OperationResult<{deleted: boolean}>>;
  
  // Network
  createNetwork(config: NetworkConfig): Promise<OperationResult<ResourceMetadata>>;
  createSecurityGroup(config: SecurityGroupConfig): Promise<OperationResult<ResourceMetadata>>;
  
  // Database
  createDatabase(config: DatabaseConfig): Promise<OperationResult<ResourceMetadata>>;
  
  // Metadata & discovery
  listRegions(): Promise<OperationResult<RegionInfo[]>>;
  getAccountInfo(): Promise<OperationResult<AccountInfo>>;
  listResourceTypes(): Promise<OperationResult<string[]>>;
  
  // Cost & monitoring
  estimateCosts(resources: ResourceMetadata[]): Promise<OperationResult<{total: number; byResource: Record<string, number>; currency: string}>>;
  getMetrics(resourceId: string, metricNames: string[]): Promise<OperationResult<MetricData[]>>;
  
  // Cleanup
  cleanup(): Promise<OperationResult<void>>;
}

/**
 * Compute configuration
 */
export interface ComputeConfig {
  name: string;
  image: string;
  machineType: string;
  region?: string;
  zone?: string;
  network?: string;
  securityGroup?: string;
  tags?: Record<string, string>;
  metadata?: Record<string, string>;
  environment?: Record<string, string>;
  diskSize?: number;
  diskType?: string;
  preemptible?: boolean; // GCP
  spotPrice?: number;   // AWS
  instanceProfile?: string; // AWS IAM role
  assumeRole?: string;   // Assume role ARN
  startupScript?: string;
  shutdownScript?: string;
}

/**
 * Compute operation status
 */
export interface ComputeStatus {
  resourceId: string;
  state: 'running' | 'stopped' | 'pending' | 'terminated' | 'failed' | 'unknown';
  publicIp?: string;
  privateIp?: string;
  launchTime?: Date;
  uptime?: number; // milliseconds
  cpuUsage?: number; // percentage
  memoryUsage?: number; // percentage
  diskUsage?: number; // percentage
}

/**
 * Storage configuration
 */
export interface StorageConfig {
  name: string;
  region?: string;
  publicRead?: boolean;
  versioning?: boolean;
  encryption?: boolean;
  lifecycleRules?: LifecycleRule[];
  tags?: Record<string, string>;
}

/**
 * Lifecycle rule
 */
export interface LifecycleRule {
  name: string;
  enabled: boolean;
  prefix?: string;
  expiration?: number; // days
  transition?: {
    days: number;
    storageClass: string;
  };
}

/**
 * Network configuration
 */
export interface NetworkConfig {
  name: string;
  cidr: string;
  region?: string;
  autoCreateSubnets?: boolean;
  subnets?: SubnetConfig[];
  tags?: Record<string, string>;
}

/**
 * Subnet configuration
 */
export interface SubnetConfig {
  name: string;
  cidr: string;
  availabilityZone?: string;
  tags?: Record<string, string>;
}

/**
 * Security group configuration
 */
export interface SecurityGroupConfig {
  name: string;
  description: string;
  vpcId?: string;
  ingressRules: IngressRule[];
  egressRules?: EgressRule[];
  tags?: Record<string, string>;
}

/**
 * Ingress rule (inbound)
 */
export interface IngressRule {
  protocol: 'tcp' | 'udp' | 'icmp' | 'all';
  fromPort?: number;
  toPort?: number;
  cidrBlocks?: string[];
  sourceSecurityGroupId?: string;
  description?: string;
}

/**
 * Egress rule (outbound)
 */
export interface EgressRule {
  protocol: 'tcp' | 'udp' | 'icmp' | 'all';
  fromPort?: number;
  toPort?: number;
  cidrBlocks?: string[];
  destinationSecurityGroupId?: string;
  description?: string;
}

/**
 * Database configuration
 */
export interface DatabaseConfig {
  name: string;
  engine: string; // mysql | postgres | mariadb | sqlserver | oracle | etc.
  version: string;
  masterUsername: string;
  masterPassword: string;
  dbName?: string;
  instanceClass?: string;
  allocatedStorage?: number; // GB
  storageType?: string;
  multiAZ?: boolean;
  backupRetentionPeriod?: number; // days
  preferredBackupWindow?: string;
  preferredMaintenanceWindow?: string;
  enableIAMDatabaseAuthentication?: boolean;
  securityGroupIds?: string[];
  subnetGroupName?: string;
  tags?: Record<string, string>;
}

/**
 * Region information
 */
export interface RegionInfo {
  name: string;
  displayName: string;
  continent?: string;
  latency?: number; // milliseconds
  available: boolean;
  availabilityZones?: string[];
  supportedServices?: string[];
}

/**
 * Account information
 */
export interface AccountInfo {
  provider: CloudProvider;
  accountId: string;
  accountName?: string;
  email?: string;
  createdAt?: Date;
  billingEnabled: boolean;
  resourceQuotas?: Record<string, {used: number; limit: number}>;
  regions?: string[];
  metadata?: Record<string, any>;
}

/**
 * Metric data point
 */
export interface MetricData {
  name: string;
  value: number;
  unit: string;
  timestamp: Date;
  statistics?: {
    average?: number;
    sum?: number;
    min?: number;
    max?: number;
    sampleCount?: number;
  };
}

/**
 * Sync operation configuration
 */
export interface SyncConfig {
  sourceProvider: CloudProvider;
  targetProviders: CloudProvider[];
  resources: string[]; // Resource IDs to sync
  strategy: 'mirror' | 'merge' | 'copy' | 'delete-target'; // Sync strategy
  dryRun?: boolean; // Validate without actually syncing
  skipIfExists?: boolean; // Don't overwrite if target exists
  transformations?: Record<string, (value: any) => any>; // Field transformations
  retryPolicy?: {
    maxAttempts: number;
    delayMs: number;
    backoffMultiplier: number;
  };
  audit?: boolean; // Log all sync activities
}

/**
 * Sync result
 */
export interface SyncResult {
  sourceProvider: CloudProvider;
  targetProviders: CloudProvider[];
  totalResources: number;
  succeededResources: number;
  failedResources: number;
  skippedResources: number;
  startTime: Date;
  endTime: Date;
  duration: number; // milliseconds
  errors: Array<{resourceId: string; provider: CloudProvider; error: string}>;
  audit?: SyncAuditEntry[];
}

/**
 * Sync audit entry (immutable append-only)
 */
export interface SyncAuditEntry {
  timestamp: Date;
  operation: 'sync_started' | 'sync_resource' | 'skip_resource' | 'sync_error' | 'sync_completed';
  sourceProvider: CloudProvider;
  targetProvider: CloudProvider;
  resourceId: string;
  status: 'success' | 'failure' | 'skipped' | 'pending';
  details?: Record<string, any>;
  hash?: string; // For tamper detection
}

/**
 * Provider registry
 */
export interface ProviderRegistry {
  register(provider: CloudProvider, instance: ICloudProvider): void;
  get(provider: CloudProvider): ICloudProvider | null;
  getAll(): ICloudProvider[];
  has(provider: CloudProvider): boolean;
  unregister(provider: CloudProvider): boolean;
}
