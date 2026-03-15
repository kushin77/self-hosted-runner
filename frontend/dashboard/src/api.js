// API Client for NexusShield Dashboard
const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:8080'
const ERROR_LOG_THROTTLE_MS = 30000
const lastErrorLogByEndpoint = new Map()

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

  const { timeoutMs = 10000, signal, ...requestOptions } = options
  const url = `${API_BASE}${endpoint}`
  const abortController = new AbortController()
  let didTimeout = false
  let externalAbortHandler = null

  if (signal) {
    externalAbortHandler = () => abortController.abort()
    signal.addEventListener('abort', externalAbortHandler, { once: true })
  }

  const timeoutId = setTimeout(() => {
    didTimeout = true
    abortController.abort()
  }, timeoutMs)
  
  try {
    const response = await fetch(url, {
      ...requestOptions,
      headers,
      signal: abortController.signal
    })

    if (!response.ok) {
      const data = await response.json().catch(() => ({}))
      throw new Error(data.error || `HTTP ${response.status}`)
    }

    return await response.json()
  } catch (error) {
    if (error?.name === 'AbortError') {
      if (didTimeout) {
        throw new Error(`Request timeout after ${timeoutMs}ms`)
      }
      throw new Error('Request canceled')
    }

    const now = Date.now()
    const lastLogTime = lastErrorLogByEndpoint.get(endpoint) || 0
    if (now - lastLogTime >= ERROR_LOG_THROTTLE_MS) {
      console.error(`API Error: ${endpoint}`, error)
      lastErrorLogByEndpoint.set(endpoint, now)
    }
    throw error
  } finally {
    clearTimeout(timeoutId)
    if (signal && externalAbortHandler) {
      signal.removeEventListener('abort', externalAbortHandler)
    }
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
  getMetrics: async (requestOptions = {}) =>
    apiFetch(`/api/v1/metrics/summary`, requestOptions),

  // Health check
  health: async (requestOptions = {}) =>
    apiFetch(`/health`, requestOptions)
}

// Clear admin key
export const clearAdminKey = () => {
  localStorage.removeItem('nexusshield_admin_key')
}
