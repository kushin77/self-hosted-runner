import React, { useEffect, useState } from 'react'
import { api } from '../api'

export default function JobDetails({ jobId, onBack }) {
  const [job, setJob] = useState(null)
  const [auditEntries, setAuditEntries] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    loadJobDetails()
  }, [jobId])

  const loadJobDetails = async () => {
    setLoading(true)
    try {
      const data = await api.getJobDetails(jobId)
      setJob(data.job)
      setAuditEntries(data.audit_entries || [])
      setError(null)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleReplay = async () => {
    if (confirm('Replay this job?')) {
      try {
        const result = await api.replayJob(jobId)
        alert(`Job replayed with new ID: ${result.new_job_id.slice(0, 8)}...`)
        onBack()
      } catch (err) {
        alert('Error replaying job: ' + err.message)
      }
    }
  }

  if (loading) {
    return <div className="loading"><div className="spinner"></div>Loading job details...</div>
  }

  if (!job) {
    return (
      <div>
        <button className="btn btn-primary" onClick={onBack}>← Back to Jobs</button>
        <div className="error" style={{ marginTop: '1rem' }}>Job not found</div>
      </div>
    )
  }

  const getStatusColor = (status) => {
    const colors = {
      queued: '#818cf8',
      running: '#60a5fa',
      completed: '#6ee7b7',
      failed: '#fca5a5',
      cancelled: '#d1d5db'
    }
    return colors[status] || '#cbd5e1'
  }

  return (
    <div>
      <button className="btn btn-primary btn-sm" onClick={onBack}>← Back to Jobs</button>

      {error && <div className="error" style={{ marginTop: '1rem' }}>{error}</div>}

      {/* Job Info */}
      <div className="card" style={{ marginTop: '1rem' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start' }}>
          <div>
            <h3 style={{ marginBottom: '1rem' }}>Job Details</h3>
            <table style={{ fontSize: '0.95rem' }}>
              <tbody>
                <tr>
                  <td style={{ width: '150px', fontWeight: 600 }}>Job ID</td>
                  <td><code>{job.id}</code></td>
                </tr>
                <tr>
                  <td fontWeight='600'>Status</td>
                  <td>
                    <span 
                      className={`badge badge-${job.status}`}
                      style={{ fontSize: '0.8rem' }}
                    >
                      {job.status}
                    </span>
                  </td>
                </tr>
                <tr>
                  <td fontWeight='600'>Source</td>
                  <td><code>{job.source}</code></td>
                </tr>
                <tr>
                  <td fontWeight='600'>Destination</td>
                  <td><code>{job.destination}</code></td>
                </tr>
                <tr>
                  <td fontWeight='600'>Mode</td>
                  <td>{job.mode}</td>
                </tr>
                <tr>
                  <td fontWeight='600'>Created</td>
                  <td>{new Date(job.created_at).toLocaleString()}</td>
                </tr>
                {job.updated_at && (
                  <tr>
                    <td fontWeight='600'>Updated</td>
                    <td>{new Date(job.updated_at).toLocaleString()}</td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
          <div>
            {job.status === 'failed' && (
              <button 
                className="btn btn-success"
                onClick={handleReplay}
              >
                Replay from DLQ
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Audit Trail */}
      <div className="card" style={{ marginTop: '1.5rem' }}>
        <h3 style={{ marginBottom: '1rem' }}>Audit Trail ({auditEntries.length} entries)</h3>
        <div style={{ maxHeight: '500px', overflowY: 'auto' }}>
          <div style={{ fontSize: '0.85rem' }}>
            {auditEntries.length === 0 ? (
              <p style={{ color: 'var(--text-secondary)' }}>No audit entries yet</p>
            ) : (
              auditEntries.map((entry, idx) => (
                <div 
                  key={idx}
                  style={{
                    padding: '0.75rem',
                    borderBottom: '1px solid var(--border)',
                    borderLeft: '3px solid var(--primary)'
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '0.25rem' }}>
                    <span style={{ fontWeight: 600, color: 'var(--primary)' }}>
                      {entry.event}
                    </span>
                    <span style={{ color: 'var(--text-secondary)' }}>
                      {new Date(entry.ts || entry.timestamp).toLocaleString()}
                    </span>
                  </div>
                  {entry.step && (
                    <div style={{ color: 'var(--text-secondary)', marginTop: '0.25rem' }}>
                      Step: <code>{entry.step}</code> — {entry.status}
                    </div>
                  )}
                  {entry.error && (
                    <div style={{ color: '#fca5a5', marginTop: '0.25rem' }}>
                      Error: {entry.error}
                    </div>
                  )}
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
