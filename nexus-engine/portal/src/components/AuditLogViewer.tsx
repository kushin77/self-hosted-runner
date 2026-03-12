import React from 'react'
import { Card, CardContent, Typography, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, CircularProgress, Alert, Box, TextField, Button, Pagination } from '@mui/material'
import { useAuditLogs } from '@/hooks/queries'

export default function AuditLogViewer() {
  const [offset, setOffset] = React.useState(0)
  const [filter, setFilter] = React.useState('')
  const limit = 50

  const { data: response, isLoading, error } = useAuditLogs(limit, offset)

  const handlePaginationChange = (event: React.ChangeEvent<unknown>, page: number) => {
    setOffset((page - 1) * limit)
  }

  const handleExport = () => {
    if (!response?.logs) return
    const csv = [
      ['Timestamp', 'Event Type', 'Provider', 'Status', 'Details'],
      ...response.logs.map(log => [
        log.timestamp,
        log.event_type,
        log.provider,
        log.status,
        JSON.stringify(log.details)
      ])
    ].map(row => row.map(cell => `"${cell}"`).join(',')).join('\n')

    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `audit-logs-${new Date().toISOString()}.csv`
    a.click()
  }

  if (error) {
    return <Alert severity="error">Failed to load audit logs: {String(error)}</Alert>
  }

  const filteredLogs = response?.logs?.filter(log =>
    log.event_type.toLowerCase().includes(filter.toLowerCase()) ||
    log.provider.toLowerCase().includes(filter.toLowerCase()) ||
    log.status.toLowerCase().includes(filter.toLowerCase())
  ) || []

  const totalPages = Math.ceil((response?.total || 0) / limit)

  return (
    <Card>
      <CardContent>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
          <Typography variant="h6">
            📋 Audit Log
          </Typography>
          <Button variant="outlined" size="small" onClick={handleExport} disabled={!response?.logs?.length}>
            Export CSV
          </Button>
        </Box>

        <TextField
          placeholder="Filter by event type, provider, or status..."
          value={filter}
          onChange={(e) => {
            setFilter(e.target.value)
            setOffset(0)
          }}
          fullWidth
          size="small"
          sx={{ mb: 2 }}
        />

        {isLoading ? (
          <CircularProgress />
        ) : filteredLogs.length === 0 ? (
          <Typography color="textSecondary">No audit logs found {filter && `matching "${filter}"`}</Typography>
        ) : (
          <>
            <TableContainer>
              <Table size="small">
                <TableHead>
                  <TableRow sx={{ backgroundColor: '#f5f5f5' }}>
                    <TableCell><strong>Timestamp</strong></TableCell>
                    <TableCell><strong>Event Type</strong></TableCell>
                    <TableCell><strong>Provider</strong></TableCell>
                    <TableCell align="center"><strong>Status</strong></TableCell>
                    <TableCell><strong>Details</strong></TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredLogs.map((log, idx) => (
                    <TableRow key={idx} sx={{ '&:hover': { backgroundColor: '#f9f9f9' } }}>
                      <TableCell sx={{ fontSize: '0.85rem' }}>
                        {new Date(log.timestamp).toLocaleString()}
                      </TableCell>
                      <TableCell sx={{ fontSize: '0.85rem' }}>
                        <code>{log.event_type}</code>
                      </TableCell>
                      <TableCell sx={{ fontSize: '0.85rem' }}>
                        {log.provider}
                      </TableCell>
                      <TableCell align="center" sx={{ fontSize: '0.85rem', color: log.status === 'success' ? '#4caf50' : '#f44336', fontWeight: 'bold' }}>
                        {log.status}
                      </TableCell>
                      <TableCell sx={{ fontSize: '0.75rem', maxWidth: 300, wordBreak: 'break-word' }}>
                        <code>{JSON.stringify(log.details).substring(0, 100)}</code>...
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>

            <Box sx={{ display: 'flex', justifyContent: 'center', mt: 2 }}>
              <Pagination
                count={totalPages}
                page={Math.floor(offset / limit) + 1}
                onChange={handlePaginationChange}
              />
            </Box>
          </>
        )}

        <Typography variant="caption" color="textSecondary" sx={{ mt: 2, display: 'block' }}>
          💡 Total logs: {response?.total || 0}. Showing {offset + 1} to {Math.min(offset + limit, response?.total || 0)}.
        </Typography>
      </CardContent>
    </Card>
  )
}
