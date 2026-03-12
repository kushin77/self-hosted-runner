import React from 'react'
import { Card, CardContent, Typography, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, CircularProgress, Alert, Button, Box } from '@mui/material'
import { useNormalizerJobs } from '@/hooks/queries'
import { portalAPI } from '@/api/client'

export default function NormalizerJobs() {
  const { data: response, isLoading, error, refetch } = useNormalizerJobs()
  const [triggering, setTriggering] = React.useState<string | null>(null)

  const handleTrigger = async (provider: string) => {
    setTriggering(provider)
    try {
      await portalAPI.triggerNormalizer(provider)
      setTimeout(() => refetch(), 500)
    } catch (err) {
      console.error('Failed to trigger normalizer:', err)
    } finally {
      setTriggering(null)
    }
  }

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'running':
        return '#ff9800'
      case 'completed':
        return '#4caf50'
      case 'failed':
        return '#f44336'
      default:
        return '#9e9e9e'
    }
  }

  if (error) {
    return <Alert severity="error">Failed to load normalizer jobs: {String(error)}</Alert>
  }

  return (
    <Card>
      <CardContent>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
          <Typography variant="h6">
            ⚙️ Normalizer Jobs
          </Typography>
          <Button variant="outlined" size="small" onClick={() => refetch()}>
            Refresh
          </Button>
        </Box>

        {isLoading ? (
          <CircularProgress />
        ) : (
          <TableContainer>
            <Table>
              <TableHead>
                <TableRow sx={{ backgroundColor: '#f5f5f5' }}>
                  <TableCell><strong>Provider</strong></TableCell>
                  <TableCell align="center"><strong>Status</strong></TableCell>
                  <TableCell align="right"><strong>Events Processed</strong></TableCell>
                  <TableCell align="right"><strong>Errors</strong></TableCell>
                  <TableCell align="right"><strong>Runtime (sec)</strong></TableCell>
                  <TableCell align="center"><strong>Last Run</strong></TableCell>
                  <TableCell align="center"><strong>Next Run</strong></TableCell>
                  <TableCell align="center"><strong>Action</strong></TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {response?.jobs?.map((job) => (
                  <TableRow key={job.provider}>
                    <TableCell><code>{job.provider}</code></TableCell>
                    <TableCell align="center">
                      <span style={{ color: getStatusColor(job.status), fontWeight: 'bold' }}>
                        {job.status}
                      </span>
                    </TableCell>
                    <TableCell align="right">{job.events_processed?.toLocaleString()}</TableCell>
                    <TableCell align="right" sx={{ color: job.error_count > 0 ? '#f44336' : '#4caf50' }}>
                      {job.error_count}
                    </TableCell>
                    <TableCell align="right">{job.runtime_sec}s</TableCell>
                    <TableCell align="center" sx={{ fontSize: '0.85rem' }}>
                      {job.last_run ? new Date(job.last_run).toLocaleTimeString() : '—'}
                    </TableCell>
                    <TableCell align="center" sx={{ fontSize: '0.85rem' }}>
                      {job.next_run ? new Date(job.next_run).toLocaleTimeString() : '—'}
                    </TableCell>
                    <TableCell align="center">
                      <Button
                        variant="contained"
                        size="small"
                        onClick={() => handleTrigger(job.provider)}
                        disabled={triggering === job.provider}
                      >
                        {triggering === job.provider ? '...' : 'Trigger'}
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        )}

        <Typography variant="caption" color="textSecondary" sx={{ mt: 2, display: 'block' }}>
          💡 Note: Normalizer jobs run on a 10-minute CronJob schedule. Click "Trigger" to run immediately (admin only).
        </Typography>
      </CardContent>
    </Card>
  )
}
