import { MetricsSummary, Job, Alert } from './store'

export interface ServerToClientEvents {
  'metrics:update': (payload: MetricsSummary) => void
  'job:event': (payload: Job) => void
  'alert:new': (payload: Alert) => void
}

export interface ClientToServerEvents {
  'job:subscribe': (jobId: string) => void
  'job:unsubscribe': (jobId: string) => void
}
