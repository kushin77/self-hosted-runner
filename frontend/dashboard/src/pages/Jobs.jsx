import React, { useEffect, useState } from 'react'
import { api } from '../api'

export default function Jobs({ onSelectJob }) {
  const [jobs, setJobs] = useState([])
  const [page, setPage] = useState(1)
  const [total, setTotal] = useState(0)
  const [limit] = useState(25)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    loadJobs()
  }, [page])

  const loadJobs = async () => {
    setLoading(true)
    try {
      const data = await api.listJobs(page, limit)
      setJobs(data.jobs || [])
      setTotal(data.total || 0)
      setError(null)
    } catch (err) {
      setError(err.message)
      setJobs([])
    } finally {
      setLoading(false)
    }
  }

  const handleCancel = async (jobId, idx) => {
    if (confirm('Cancel this job?')) {
      try {
        await api.cancelJob(jobId)
        loadJobs()
      } catch (err) {
        alert('Error cancelling job: ' + err.message)
      }
    }
  }

  const pages = Math.ceil(total / limit)

  const getStatusBadge = (status) => {
    return <span className={`badge badge-${status}`}>{status}</span>
  }

  return (
    <div>
      <h2 style={{ marginBottom: '1.5rem' }}>Migration Jobs</h2>

      {error && <div className="error">{error}</div>}

      {loading ? (
        <div className="loading"><div className="spinner"></div>Loading jobs...</div>
      ) : jobs.length === 0 ? (
        <div className="card" style={{ textAlign: 'center', padding: '3rem' }}>
          <p>No jobs found</p>
        </div>
      ) : (
        <>
          <div className="table-container">
            <table>
              <thead>
                <tr>
                  <th>Job ID</th>
                  <th>Source</th>
                  <th>Destination</th>
                  <th>Status</th>
                  <th>Created</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody>
                {jobs.map((job) => (
                  <tr key={job.id}>
                    <td>
                      <code style={{ fontSize: '0.8rem', color: 'var(--primary)' }}>
                        {job.id.slice(0, 8)}...
                      </code>
                    </td>
                    <td style={{ fontSize: '0.9rem' }}>{job.source}</td>
                    <td style={{ fontSize: '0.9rem' }}>{job.destination}</td>
                    <td>{getStatusBadge(job.status)}</td>
                    <td style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
                      {new Date(job.created_at).toLocaleString()}
                    </td>
                    <td>
                      <div style={{ display: 'flex', gap: '0.5rem' }}>
                        <button 
                          className="btn btn-primary btn-sm"
                          onClick={() => onSelectJob(job.id)}
                        >
                          Details
                        </button>
                        {job.status === 'queued' || job.status === 'running' ? (
                          <button 
                            className="btn btn-danger btn-sm"
                            onClick={() => handleCancel(job.id)}
                          >
                            Cancel
                          </button>
                        ) : null}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          <div className="pagination">
            <button 
              onClick={() => setPage(p => Math.max(1, p - 1))}
              disabled={page === 1}
            >
              ← Previous
            </button>
            <span>Page {page} of {pages}</span>
            <button 
              onClick={() => setPage(p => Math.min(pages, p + 1))}
              disabled={page >= pages}
            >
              Next →
            </button>
          </div>
        </>
      )}
    </div>
  )
}
