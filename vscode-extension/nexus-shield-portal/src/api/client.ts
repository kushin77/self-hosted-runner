/**
 * NexusShield API Client
 * 
 * Handles all HTTP communication with the NexusShield backend API
 */

import axios, { AxiosInstance } from 'axios';
import { Logger } from '../utils/logger';

export interface Migration {
  id: string;
  name: string;
  source: string;
  target: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  progress: number;
  createdAt: string;
  updatedAt: string;
  createdBy: string;
}

export interface HealthStatus {
  status: 'healthy' | 'degraded' | 'unhealthy';
  services: {
    api: boolean;
    database: boolean;
    cache: boolean;
  };
  uptime: number;
  timestamp: string;
}

export interface Metrics {
  activeMigrations: number;
  completedMigrations: number;
  failedMigrations: number;
  healthStatus: string;
  apiLatency: number;
  systemLoad: number;
}

export class NexusShieldAPI {
  private client: AxiosInstance;
  private apiUrl: string;

  constructor(apiUrl: string, apiKey: string, private logger: Logger) {
    this.apiUrl = apiUrl;
    this.client = axios.default.create({
      baseURL: apiUrl,
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
        ...(apiKey && { 'X-API-Key': apiKey })
      }
    });

    // Add response interceptor for error logging
    this.client.interceptors.response.use(
      response => response,
      error => {
        this.logger.error(`API Error: ${error.message}`);
        throw error;
      }
    );
  }

  /**
   * Check API health
   */
  async health(): Promise<HealthStatus> {
    const response = await this.client.get<HealthStatus>('/health');
    return response.data;
  }

  /**
   * Get system metrics
   */
  async getMetrics(): Promise<Metrics> {
    const response = await this.client.get<Metrics>('/api/v1/metrics');
    this.logger.info('Fetched metrics');
    return response.data;
  }

  /**
   * List all migrations
   */
  async listMigrations(limit: number = 50): Promise<Migration[]> {
    const response = await this.client.get<Migration[]>(
      `/api/v1/migrations?limit=${limit}`
    );
    this.logger.info(`Fetched ${response.data.length} migrations`);
    return response.data;
  }

  /**
   * Get migration by ID
   */
  async getMigration(id: string): Promise<Migration> {
    const response = await this.client.get<Migration>(`/api/v1/migrations/${id}`);
    return response.data;
  }

  /**
   * Create a new migration
   */
  async createMigration(data: {
    name: string;
    source: string;
    target: string;
    createdBy: string;
  }): Promise<Migration> {
    const response = await this.client.post<Migration>(
      '/api/v1/migrations',
      data
    );
    this.logger.info(`Created migration: ${response.data.id}`);
    return response.data;
  }

  /**
   * Update migration
   */
  async updateMigration(
    id: string,
    data: Partial<Migration>
  ): Promise<Migration> {
    const response = await this.client.patch<Migration>(
      `/api/v1/migrations/${id}`,
      data
    );
    this.logger.info(`Updated migration: ${id}`);
    return response.data;
  }

  /**
   * Start migration
   */
  async startMigration(id: string): Promise<Migration> {
    return this.updateMigration(id, { status: 'running' });
  }

  /**
   * Cancel migration
   */
  async cancelMigration(id: string): Promise<Migration> {
    const response = await this.client.post<Migration>(
      `/api/v1/migrations/${id}/cancel`
    );
    return response.data;
  }

  /**
   * Get migration status
   */
  async getMigrationStatus(id: string): Promise<{
    id: string;
    status: string;
    progress: number;
    message: string;
  }> {
    const response = await this.client.get(
      `/api/v1/migrations/${id}/status`
    );
    return response.data;
  }

  /**
   * Get audit log
   */
  async getAuditLog(limit: number = 100): Promise<any[]> {
    const response = await this.client.get(
      `/api/v1/audit?limit=${limit}`
    );
    this.logger.info(`Fetched ${response.data.length} audit entries`);
    return response.data;
  }

  /**
   * Get recent activity
   */
  async getRecentActivity(limit: number = 20): Promise<any[]> {
    const response = await this.client.get(
      `/api/v1/activity?limit=${limit}`
    );
    return response.data;
  }

  /**
   * Deploy migration job to cloud
   */
  async deployMigration(id: string, cloud: string): Promise<{
    jobId: string;
    status: string;
  }> {
    const response = await this.client.post(
      `/api/v1/migrations/${id}/deploy`,
      { cloud }
    );
    return response.data;
  }

  /**
   * Get migration logs
   */
  async getMigrationLogs(id: string, lines: number = 100): Promise<string> {
    const response = await this.client.get(
      `/api/v1/migrations/${id}/logs?lines=${lines}`
    );
    return response.data;
  }

  /**
   * Test connection to cloud
   */
  async testCloudConnection(cloud: string, credentials: any): Promise<{
    status: boolean;
    message: string;
  }> {
    const response = await this.client.post(
      `/api/v1/credentials/test`,
      {
        cloud,
        credentials
      }
    );
    return response.data;
  }
}
