import axios, { AxiosInstance } from 'axios'

interface HealthResponse {
  status: string
  uptime_sec: number
  timestamp: string
}

interface KafkaMetrics {
  raw_topic: {
    queue_depth: number
    consumer_lag: number
  }
  normalized_topic: {
    queue_depth: number
    producer_rate_eps: number
  }
}

interface NormalizerJob {
  provider: string
  status: string
  last_run: string
  next_run: string
  events_processed: number
  error_count: number
  runtime_sec: number
}

interface NormalizerJobsResponse {
  jobs: NormalizerJob[]
}

interface AuditLog {
  timestamp: string
  event_type: string
  provider: string
  status: string
  details: any
}

interface AuditLogResponse {
  logs: AuditLog[]
  total: number
}

class PortalAPIClient {
  private client: AxiosInstance

  constructor(baseURL: string = '/api') {
    this.client = axios.create({
      baseURL,
      headers: {
        'Content-Type': 'application/json',
      },
      timeout: 10000,
    })
  }

  async getHealth(): Promise<HealthResponse> {
    const { data } = await this.client.get<HealthResponse>('/health')
    return data
  }

  async getKafkaMetrics(): Promise<KafkaMetrics> {
    const { data } = await this.client.get<KafkaMetrics>('/kafka/metrics')
    return data
  }

  async getNormalizerJobs(): Promise<NormalizerJobsResponse> {
    const { data } = await this.client.get<NormalizerJobsResponse>('/normalizer/jobs')
    return data
  }

  async triggerNormalizer(provider: string): Promise<void> {
    await this.client.post('/normalizer/trigger', { provider })
  }

  async getAuditLogs(limit: number = 100, offset: number = 0): Promise<AuditLogResponse> {
    const { data } = await this.client.get<AuditLogResponse>('/audit/logs', {
      params: { limit, offset }
    })
    return data
  }
}

export const portalAPI = new PortalAPIClient()
export type { HealthResponse, KafkaMetrics, NormalizerJob, AuditLog }
