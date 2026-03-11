import React, { useEffect, useState } from 'react'
import { api } from '../api'

export default function Dashboard({ onNavigate }) {
  const [metrics, setMetrics] = useState(null)
  const [health, setHealth] = useState('unknown')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    loadData()
    const interval = setInterval(loadData, 5000) // Refresh every 5s
    return () => clearInterval(interval)
  }, [])

  const loadData = async () => {
    try {
      const [metricsData] = await Promise.all([
        api.getMetrics().catch(() => null)
      ])
      setMetrics(metricsData)
      setError(null)
      
      // Check health
      try {
        await api.health()
        setHealth('healthy')
      } catch {
        setHealth('unhealthy')
      }
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return <div className="loading"><div className="spinner"></div>Loading dashboard...</div>
  }

  const stats = [
    { label: 'Jobs Queued', value: metrics?.jobs_queued || 0, color: 'primary' },
    { label: 'Jobs Running', value: metrics?.jobs_running || 0, color: 'primary' },
    { label: 'Jobs Completed', value: metrics?.jobs_completed || 0, color: 'success' },
    { label: 'Jobs Failed', value: metrics?.jobs_failed || 0, color: 'danger' }
  ]

  return (
    <div>
      <h2 style={{ marginBottom: '1.5rem' }}>Dashboard</h2>

      {error && <div className="error">{error}</div>}

      {/* Health Status */}
      <div className="card" style={{ marginBottom: '2rem', padding: '1rem' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)' }}>System Status</p>
            <p style={{ fontSize: '1.2rem', fontWeight: 600, marginTop: '0.5rem' }}>
              API: <span style={{ color: health === 'healthy' ? '#10b981' : '#ef4444' }}>
                {health === 'healthy' ? '✓ Healthy' : '✗ Unhealthy'}
              </span>
            </p>
          </div>
          <button 
            className="btn btn-primary btn-sm"
            onClick={loadData}
          >
            Refresh
          </button>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid">
        {stats.map((stat, idx) => (
          <div key={idx} className="stat-card">
            <div className="stat-label">{stat.label}</div>
            <div className="stat-number">{stat.value}</div>
          </div>
        ))}
      </div>

      {/* Summary Info */}
      {metrics && (
        <div className="card">
          <h3 style={{ marginBottom: '1rem' }}>Summary</h3>
          <table>
            <tbody>
              <tr>
                <td style={{ width: '200px' }}>Total Jobs</td>
                <td><strong>{metrics.total_jobs}</strong></td>
              </tr>
              <tr>
                <td>Average Duration</td>
                <td><strong>{metrics.avg_duration_s?.toFixed(2) || 'N/A'} seconds</strong></td>
              </tr>
              <tr>
                <td>Success Rate</td>
                <td>
                  <strong>
                    {metrics.total_jobs > 0
                      ? ((metrics.jobs_completed / metrics.total_jobs) * 100).toFixed(1)
                      : 'N/A'
                    }%
                  </strong>
                </td>
              </tr>
              <tr>
                <td>Last Updated</td>
                <td>{new Date(metrics.timestamp).toLocaleString()}</td>
              </tr>
            </tbody>
          </table>
        </div>
      )}

      {/* Quick Links */}
      <div style={{ marginTop: '2rem', display: 'flex', gap: '1rem' }}>
        <button 
          className="btn btn-primary"
          onClick={() => onNavigate('jobs')}
        >
          View All Jobs →
        </button>
        <button 
          className="btn btn-primary"
          onClick={() => onNavigate('metrics')}
        >
          View Metrics →
        </button>
      </div>
    </div>
  )
}
