// API Client for NexusShield Dashboard
const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:8080'

// Get admin key from localStorage
const getAdminKey = () => {
  let key = localStorage.getItem('nexusshield_admin_key')
  if (!key) {
    key = prompt('Enter admin key:')
    if (key) {
      localStorage.setItem('nexusshield_admin_key', key)
    }
  }
  return key
}

// API request helper
const apiFetch = async (endpoint, options = {}) => {
  const adminKey = getAdminKey()
  if (!adminKey) {
    throw new Error('Admin key required')
  }

  const headers = {
    'Content-Type': 'application/json',
    'X-Admin-Key': adminKey,
    ...options.headers
  }

  const url = `${API_BASE}${endpoint}`
  
  try {
    const response = await fetch(url, {
      ...options,
      headers,
      timeout: 10000
    })

    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      throw new Error(data.error || `HTTP ${response.status}`)
    }

    return await response.json()
  } catch (error) {
    console.error(`API Error: ${endpoint}`, error)
    throw error
  }
}

// API Methods
export const api = {
  // List all jobs with pagination
  listJobs: async (page = 1, limit = 50) =>
    apiFetch(`/api/v1/jobs?page=${page}&limit=${limit}`),

  // Get job details with audit trail
  getJobDetails: async (jobId) =>
    apiFetch(`/api/v1/jobs/${jobId}/details`),

  // Cancel a job
  cancelJob: async (jobId) =>
    apiFetch(`/api/v1/jobs/${jobId}`, { method: 'DELETE' }),

  // Replay a failed job
  replayJob: async (jobId) =>
    apiFetch(`/api/v1/jobs/${jobId}/replay`, { method: 'POST' }),

  // Get system metrics summary
  getMetrics: async () =>
    apiFetch(`/api/v1/metrics/summary`),

  // Health check
  health: async () =>
    apiFetch(`/health`)
}

// Clear admin key
export const clearAdminKey = () => {
  localStorage.removeItem('nexusshield_admin_key')
}
