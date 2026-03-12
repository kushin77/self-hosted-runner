import React from 'react'
import { Box, Card, CardContent, Typography, Grid, CircularProgress, Alert } from '@mui/material'
import { useHealth, useKafkaMetrics } from '@/hooks/queries'

export default function Dashboard() {
  const { data: health, isLoading: healthLoading, error: healthError } = useHealth()
  const { data: kafka, isLoading: kafkaLoading, error: kafkaError } = useKafkaMetrics()

  const getHealthColor = (status?: string) => {
    switch (status) {
      case 'healthy':
        return '#4caf50'
      case 'degraded':
        return '#ff9800'
      case 'unhealthy':
        return '#f44336'
      default:
        return '#9e9e9e'
    }
  }

  if (healthError) {
    return <Alert severity="error">Failed to load dashboard: {String(healthError)}</Alert>
  }

  return (
    <Grid container spacing={3}>
      {/* System Health */}
      <Grid item xs={12} sm={6} md={3}>
        <Card>
          <CardContent sx={{ textAlign: 'center' }}>
            <Typography color="textSecondary" gutterBottom>
              System Health
            </Typography>
            {healthLoading ? (
              <CircularProgress />
            ) : (
              <>
                <CircularProgress
                  variant="determinate"
                  value={health?.status === 'healthy' ? 100 : health?.status === 'degraded' ? 50 : 0}
                  size={80}
                  sx={{ color: getHealthColor(health?.status), my: 2 }}
                />
                <Typography variant="h6" sx={{ color: getHealthColor(health?.status), fontWeight: 'bold' }}>
                  {health?.status?.toUpperCase()}
                </Typography>
                <Typography variant="caption" color="textSecondary">
                  Uptime: {health ? Math.floor(health.uptime_sec / 60) : 0} min
                </Typography>
              </>
            )}
          </CardContent>
        </Card>
      </Grid>

      {/* Kafka Raw Queue */}
      <Grid item xs={12} sm={6} md={3}>
        <Card>
          <CardContent>
            <Typography color="textSecondary" gutterBottom>
              Raw Queue Depth
            </Typography>
            {kafkaLoading ? (
              <CircularProgress />
            ) : (
              <>
                <Typography variant="h4" sx={{ fontWeight: 'bold', color: '#1976d2' }}>
                  {kafka?.raw_topic?.queue_depth?.toLocaleString() || 0}
                </Typography>
                <Typography variant="caption" color="textSecondary">
                  Consumer Lag: {kafka?.raw_topic?.consumer_lag || 0} msgs
                </Typography>
              </>
            )}
          </CardContent>
        </Card>
      </Grid>

      {/* Kafka Normalized Queue */}
      <Grid item xs={12} sm={6} md={3}>
        <Card>
          <CardContent>
            <Typography color="textSecondary" gutterBottom>
              Normalized Queue Depth
            </Typography>
            {kafkaLoading ? (
              <CircularProgress />
            ) : (
              <>
                <Typography variant="h4" sx={{ fontWeight: 'bold', color: '#4caf50' }}>
                  {kafka?.normalized_topic?.queue_depth?.toLocaleString() || 0}
                </Typography>
                <Typography variant="caption" color="textSecondary">
                  Producer Rate: {kafka?.normalized_topic?.producer_rate_eps?.toFixed(2) || 0} eps
                </Typography>
              </>
            )}
          </CardContent>
        </Card>
      </Grid>

      {/* Status Indicator */}
      <Grid item xs={12} sm={6} md={3}>
        <Card sx={{ backgroundColor: getHealthColor(health?.status) + '20', borderLeft: `4px solid ${getHealthColor(health?.status)}` }}>
          <CardContent>
            <Typography color="textSecondary" gutterBottom>
              Pipeline Status
            </Typography>
            <Typography variant="body2">
              {health?.status === 'healthy' && '✅ All systems operational'}
              {health?.status === 'degraded' && '⚠️ Performance degraded'}
              {health?.status === 'unhealthy' && '❌ Service unavailable'}
            </Typography>
            <Typography variant="caption" color="textSecondary" sx={{ mt: 1, display: 'block' }}>
              Last Updated: {health?.timestamp ? new Date(health.timestamp).toLocaleTimeString() : 'N/A'}
            </Typography>
          </CardContent>
        </Card>
      </Grid>

      {/* System Info */}
      <Grid item xs={12}>
        <Card>
          <CardContent>
            <Typography variant="h6" gutterBottom>
              📊 System Overview
            </Typography>
            <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 2 }}>
              <Box>
                <Typography variant="caption" color="textSecondary">Ingestion Endpoint</Typography>
                <Typography variant="body2">/api/ingest (HTTP POST)</Typography>
              </Box>
              <Box>
                <Typography variant="caption" color="textSecondary">Database</Typography>
                <Typography variant="body2">PostgreSQL 15 (RLS-enabled)</Typography>
              </Box>
              <Box>
                <Typography variant="caption" color="textSecondary">Message Queue</Typography>
                <Typography variant="body2">Apache Kafka (nexus.discovery.*)</Typography>
              </Box>
              <Box>
                <Typography variant="caption" color="textSecondary">Normalizers</Typography>
                <Typography variant="body2">Kubernetes CronJob (10-min interval)</Typography>
              </Box>
            </Box>
          </CardContent>
        </Card>
      </Grid>
    </Grid>
  )
}
