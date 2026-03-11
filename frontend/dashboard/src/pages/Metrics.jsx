import React, { useEffect, useState } from 'react'
import { api } from '../api'

export default function Metrics() {
  const [metrics, setMetrics] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    loadMetrics()
    const interval = setInterval(loadMetrics, 5000)
    return () => clearInterval(interval)
  }, [])

  const loadMetrics = async () => {
    try {
      const data = await api.getMetrics()
      setMetrics(data)
      setError(null)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return <div className="loading"><div className="spinner"></div>Loading metrics...</div>
  }

  if (!metrics) {
    return <div className="error">Failed to load metrics</div>
  }

  const metricCards = [
    { label: 'Total Jobs', value: metrics.total_jobs, unit: '' },
    { label: 'Jobs Queued', value: metrics.jobs_queued, unit: '' },
    { label: 'Jobs Running', value: metrics.jobs_running, unit: '' },
    { label: 'Jobs Completed', value: metrics.jobs_completed, unit: '' },
    { label: 'Jobs Failed', value: metrics.jobs_failed, unit: '' },
    { label: 'Jobs Cancelled', value: metrics.jobs_cancelled, unit: '' },
    { label: 'Avg Duration', value: metrics.avg_duration_s?.toFixed(2), unit: 's' },
    { 
      label: 'Success Rate', 
      value: metrics.total_jobs > 0 
        ? ((metrics.jobs_completed / metrics.total_jobs) * 100).toFixed(1) 
        : 'N/A', 
      unit: '%' 
    }
  ]

  const errorRate = metrics.total_jobs > 0 
    ? ((metrics.jobs_failed / metrics.total_jobs) * 100).toFixed(1)
    : '0'

  return (
    <div>
      <h2 style={{ marginBottom: '1.5rem' }}>System Metrics</h2>

      {error && <div className="error">{error}</div>}

      {/* Metrics Grid */}
      <div className="grid">
        {metricCards.map((card, idx) => (
          <div key={idx} className="stat-card">
            <div className="stat-label">{card.label}</div>
            <div className="stat-number">
              {card.value}{card.unit}
            </div>
          </div>
        ))}
      </div>

      {/* Summary Table */}
      <div className="card">
        <h3 style={{ marginBottom: '1rem' }}>Job Statistics</h3>
        <table>
          <tbody>
            <tr>
              <td style={{ width: '250px' }}>Total Jobs</td>
              <td><strong>{metrics.total_jobs}</strong></td>
            </tr>
            <tr>
              <td>Completed</td>
              <td><strong>{metrics.jobs_completed}</strong> ({((metrics.jobs_completed / (metrics.total_jobs || 1)) * 100).toFixed(1)}%)</td>
            </tr>
            <tr>
              <td>Failed</td>
              <td><strong style={{ color: '#fca5a5' }}>{metrics.jobs_failed}</strong> ({errorRate}%)</td>
            </tr>
            <tr>
              <td>Currently Running</td>
              <td><strong>{metrics.jobs_running}</strong></td>
            </tr>
            <tr>
              <td>Queued</td>
              <td><strong>{metrics.jobs_queued}</strong></td>
            </tr>
            <tr>
              <td>Cancelled</td>
              <td><strong>{metrics.jobs_cancelled}</strong></td>
            </tr>
            <tr>
              <td>Average Duration</td>
              <td><strong>{metrics.avg_duration_s?.toFixed(2) || 'N/A'}</strong> seconds</td>
            </tr>
          </tbody>
        </table>
      </div>

      {/* API Endpoint Info */}
      <div className="card" style={{ marginTop: '2rem' }}>
        <h3 style={{ marginBottom: '1rem' }}>Raw Metrics Data</h3>
        <pre style={{
          background: 'var(--bg-darker)',
          padding: '1rem',
          borderRadius: '4px',
          overflow: 'auto',
          fontSize: '0.8rem',
          color: 'var(--text-secondary)'
        }}>
          {JSON.stringify(metrics, null, 2)}
        </pre>
      </div>
    </div>
  )
}
