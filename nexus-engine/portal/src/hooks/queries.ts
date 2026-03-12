import { useQuery } from '@tanstack/react-query'
import { portalAPI } from '@/api/client'

export function useHealth() {
  return useQuery({
    queryKey: ['health'],
    queryFn: () => portalAPI.getHealth(),
  })
}

export function useKafkaMetrics() {
  return useQuery({
    queryKey: ['kafka-metrics'],
    queryFn: () => portalAPI.getKafkaMetrics(),
  })
}

export function useNormalizerJobs() {
  return useQuery({
    queryKey: ['normalizer-jobs'],
    queryFn: () => portalAPI.getNormalizerJobs(),
  })
}

export function useAuditLogs(limit: number = 100, offset: number = 0) {
  return useQuery({
    queryKey: ['audit-logs', limit, offset],
    queryFn: () => portalAPI.getAuditLogs(limit, offset),
  })
}
