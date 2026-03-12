import React from 'react'
import { Card, CardContent, Typography, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, CircularProgress, Alert } from '@mui/material'
import { useKafkaMetrics } from '@/hooks/queries'

export default function KafkaMetrics() {
  const { data: metrics, isLoading, error } = useKafkaMetrics()

  if (error) {
    return <Alert severity="error">Failed to load Kafka metrics: {String(error)}</Alert>
  }

  return (
    <Card>
      <CardContent>
        <Typography variant="h6" gutterBottom>
          📡 Kafka Topics
        </Typography>

        {isLoading ? (
          <CircularProgress />
        ) : (
          <TableContainer>
            <Table>
              <TableHead>
                <TableRow sx={{ backgroundColor: '#f5f5f5' }}>
                  <TableCell><strong>Topic</strong></TableCell>
                  <TableCell align="right"><strong>Queue Depth</strong></TableCell>
                  <TableCell align="right"><strong>Consumer Lag</strong></TableCell>
                  <TableCell align="right"><strong>Producer Rate (eps)</strong></TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                <TableRow>
                  <TableCell><code>nexus.discovery.raw</code></TableCell>
                  <TableCell align="right">{metrics?.raw_topic?.queue_depth?.toLocaleString()}</TableCell>
                  <TableCell align="right">{metrics?.raw_topic?.consumer_lag?.toLocaleString()}</TableCell>
                  <TableCell align="right">—</TableCell>
                </TableRow>
                <TableRow>
                  <TableCell><code>nexus.discovery.normalized</code></TableCell>
                  <TableCell align="right">{metrics?.normalized_topic?.queue_depth?.toLocaleString()}</TableCell>
                  <TableCell align="right">—</TableCell>
                  <TableCell align="right">{metrics?.normalized_topic?.producer_rate_eps?.toFixed(2)}</TableCell>
                </TableRow>
              </TableBody>
            </Table>
          </TableContainer>
        )}

        <Typography variant="caption" color="textSecondary" sx={{ mt: 2, display: 'block' }}>
          💡 Tip: Monitor queue depth for ingestion bottlenecks. Consumer lag indicates normalizer lag.
        </Typography>
      </CardContent>
    </Card>
  )
}
