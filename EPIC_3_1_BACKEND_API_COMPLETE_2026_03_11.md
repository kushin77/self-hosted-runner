# EPIC-3.1: Backend API Endpoint Extensions
**Date:** March 11, 2026 | **Status:** ✅ COMPLETE | **Version:** 1.0

---

## Executive Summary

**Phase 3a of Browser Migration Dashboard is complete.** All five new backend API endpoints implemented and integrated with existing NexusShield infrastructure.

**New Endpoints (5 total):**
1. ✅ `GET /api/v1/jobs` — List all migration jobs with pagination
2. ✅ `GET /api/v1/jobs/{job_id}/details` — Get job details with full audit trail
3. ✅ `DELETE /api/v1/jobs/{job_id}` — Cancel in-progress job
4. ✅ `POST /api/v1/jobs/{job_id}/replay` — Retry failed job from DLQ
5. ✅ `GET /api/v1/metrics/summary` — Get system metrics summary

All endpoints: 
- ✅ Require X-Admin-Key authentication (admin decorator)
- ✅ Log all operations to immutable audit trail
- ✅ Return proper HTTP status codes
- ✅ Support idempotent operations
- ✅ Increment Prometheus metrics
- ✅ Handle errors gracefully

---

## API Specification

### 1. List All Jobs with Pagination

**Endpoint:** `GET /api/v1/jobs?page=1&limit=50`

**Authentication:** Required (X-Admin-Key header)

**Query Parameters:**
- `page` (int, optional, default=1) — 1-based page number
- `limit` (int, optional, default=50) — Results per page (max 200)

**Response (200 OK):**
```json
{
  "jobs": [
    {
      "id": "job-uuid-1",
      "source": "s3://source-bucket",
      "destination": "gs://dest-bucket",
      "mode": "live",
      "status": "completed",
      "created_at": "2026-03-11T14:00:00Z",
      "updated_at": "2026-03-11T14:05:30Z"
    }
  ],
  "total": 127,
  "page": 1,
  "limit": 50,
  "pages": 3
}
```

**Error Responses:**
- `401 Unauthorized` — Missing or invalid X-Admin-Key
- `400 Bad Request` — Invalid pagination params (page < 1, limit < 1, limit > 200)
- `500 Internal Server Error` — Server error

**Usage Example:**
```bash
curl -X GET "http://localhost:8080/api/v1/jobs?page=1&limit=25" \
  -H "X-Admin-Key: [REDACTED]"
```

---

### 2. Get Job Details with Audit Trail

**Endpoint:** `GET /api/v1/jobs/{job_id}/details`

**Authentication:** Required (X-Admin-Key header)

**Path Parameters:**
- `job_id` (string) — UUID of the job to retrieve

**Response (200 OK):**
```json
{
  "job": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "source": "s3://bucket-name",
    "destination": "gs://bucket-name",
    "mode": "live",
    "status": "completed",
    "created_at": "2026-03-11T14:00:00Z",
    "updated_at": "2026-03-11T14:05:30Z"
  },
  "audit_entries": [
    {
      "job_id": "550e8400-e29b-41d4-a716-446655440000",
      "event": "job_queued",
      "timestamp": "2026-03-11T14:00:05Z",
      "payload": { ... }
    },
    {
      "job_id": "550e8400-e29b-41d4-a716-446655440000",
      "event": "job_started",
      "timestamp": "2026-03-11T14:00:10Z"
    },
    {
      "job_id": "550e8400-e29b-41d4-a716-446655440000",
      "event": "step_start",
      "step": "validate_source",
      "timestamp": "2026-03-11T14:00:11Z"
    }
  ],
  "audit_count": 25
}
```

**Error Responses:**
- `401 Unauthorized` — Missing or invalid X-Admin-Key
- `404 Not Found` — Job not found
- `500 Internal Server Error` — Server error

**Usage Example:**
```bash
curl -X GET "http://localhost:8080/api/v1/jobs/550e8400-e29b-41d4-a716-446655440000/details" \
  -H "X-Admin-Key: [REDACTED]"
```

---

### 3. Cancel In-Progress Job

**Endpoint:** `DELETE /api/v1/jobs/{job_id}`

**Authentication:** Required (X-Admin-Key header)

**Path Parameters:**
- `job_id` (string) — UUID of the job to cancel

**Request Body:** (not required)

**Response (200 OK):**
```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "cancelled"
}
```

**Error Responses:**
- `401 Unauthorized` — Missing or invalid X-Admin-Key
- `404 Not Found` — Job not found
- `400 Bad Request` — Cannot cancel job in `completed`, `failed`, or `cancelled` status
- `500 Internal Server Error` — Server error

**Valid Status Transitions:**
- `queued` → `cancelled` ✅
- `running` → `cancelled` ✅
- `completed` → `cancelled` ❌ (error 400)
- `failed` → `cancelled` ❌ (error 400)
- `cancelled` → `cancelled` ❌ (error 400)

**Usage Example:**
```bash
curl -X DELETE "http://localhost:8080/api/v1/jobs/550e8400-e29b-41d4-a716-446655440000" \
  -H "X-Admin-Key: [REDACTED]"
```

---

### 4. Replay Failed Job from DLQ

**Endpoint:** `POST /api/v1/jobs/{job_id}/replay`

**Authentication:** Required (X-Admin-Key header)

**Path Parameters:**
- `job_id` (string) — UUID of the failed job to retry

**Request Body:** (not required)

**Response (201 Created):**
```json
{
  "new_job_id": "660f9500-f30c-52e5-b827-557766551111",
  "original_job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "queued"
}
```

**Behavior:**
- Creates NEW job with same source/destination/mode parameters
- Assigns new UUID to retry attempt
- Original job remains in `failed` status for audit purposes
- New job immediately queued for execution
- Immutable audit trail records replay linkage

**Error Responses:**
- `401 Unauthorized` — Missing or invalid X-Admin-Key
- `404 Not Found` — Job not found
- `400 Bad Request` — Can only replay `failed` status jobs
- `500 Internal Server Error` — Server error

**Valid Replay Status:**
- `failed` → new job created ✅
- `completed` → error 400 ❌
- `running` → error 400 ❌
- `queued` → error 400 ❌
- `cancelled` → error 400 ❌

**Usage Example:**
```bash
curl -X POST "http://localhost:8080/api/v1/jobs/550e8400-e29b-41d4-a716-446655440000/replay" \
  -H "X-Admin-Key: [REDACTED]"
```

---

### 5. Get System Metrics Summary

**Endpoint:** `GET /api/v1/metrics/summary`

**Authentication:** Required (X-Admin-Key header)

**Response (200 OK):**
```json
{
  "jobs_queued": 3,
  "jobs_running": 1,
  "jobs_completed": 127,
  "jobs_failed": 5,
  "jobs_cancelled": 2,
  "total_jobs": 138,
  "avg_duration_s": 285.43,
  "timestamp": "2026-03-11T14:45:30Z"
}
```

**Metric Definitions:**
- `jobs_queued` — Jobs waiting to start
- `jobs_running` — Currently executing jobs
- `jobs_completed` — Successfully finished jobs
- `jobs_failed` — Jobs that encountered errors
- `jobs_cancelled` — User-cancelled jobs
- `total_jobs` — Sum of all jobs
- `avg_duration_s` — Average job execution time (completed jobs only)

**Error Responses:**
- `401 Unauthorized` — Missing or invalid X-Admin-Key
- `500 Internal Server Error` — Server error

**Usage Example:**
```bash
curl -X GET "http://localhost:8080/api/v1/metrics/summary" \
  -H "X-Admin-Key: [REDACTED]" \
  -H "Accept: application/json"
```

---

## Implementation Details

### File Changes

**Modified: `scripts/cloudrun/app.py`**
- Added 5 new route handlers with `@require_admin` decorator
- All handlers follow existing Flask patterns
- Error handling with audit trail logging
- Prometheus metrics incremented for each endpoint

**Modified: `scripts/cloudrun/persistent_jobs.py`**
- Added `count_jobs()` function — Returns total job count
- Enhanced `list_jobs()` function — Supports pagination (limit, offset)
- Added `get_stats()` function — Computes job statistics
- Sorting by created_at (newest first) for consistent pagination

### Design Decisions

1. **Pagination Strategy:** Offset-based (supports direct page access)
2. **Sorting Order:** Newest jobs first (created_at descending)
3. **Error Responses:** HTTP status codes follow REST conventions
4. **Audit Trail:** ALL operations logged (list, cancel, replay, stats)
5. **Idempotency:** Job operations are idempotent (safe to retry)
6. **Authentication:** All new endpoints require admin key (no public access)
7. **Metrics:** Prometheus instrumentation on every endpoint

### Backward Compatibility

- ✅ Existing endpoints unchanged
- ✅ No breaking API changes
- ✅ Existing job structure extended (not modified)
- ✅ Admin key authentication consistent with existing code

---

## Testing Procedures

### Pre-Deployment Testing

**Test 1: List Jobs Pagination**
```bash
# Should return paginated job list
curl -s -X GET "http://localhost:8080/api/v1/jobs?page=1&limit=10" \
  -H "X-Admin-Key: test-key" | jq '.jobs | length'
# Expected: <= 10

# Test page bounds
curl -s -X GET "http://localhost:8080/api/v1/jobs?page=999" \
  -H "X-Admin-Key: test-key" | jq '.jobs | length'
# Expected: 0 (empty array)
```

**Test 2: Job Details with Audit**
```bash
# Create a test job first
JOB_ID=$(curl -s -X POST http://localhost:8080/api/v1/migrate \
  -H "X-Admin-Key: test-key" \
  -H "Content-Type: application/json" \
  -d '{"source":"s3://b","destination":"gs://b"}' | jq -r '.job_id')

# Retrieve its details
curl -s -X GET "http://localhost:8080/api/v1/jobs/$JOB_ID/details" \
  -H "X-Admin-Key: test-key" | jq '.audit_entries | length'
# Expected: >= 2 (at least queued + dry_run_completed events)
```

**Test 3: Cancel Job**
```bash
# Create and immediately cancel a job
JOB_ID=$(curl -s -X POST http://localhost:8080/api/v1/migrate \
  -H "X-Admin-Key: test-key" \
  -H "Content-Type: application/json" \
  -d '{"source":"s3://b","destination":"gs://b"}' | jq -r '.job_id')

# Cancel it
curl -s -X DELETE "http://localhost:8080/api/v1/jobs/$JOB_ID" \
  -H "X-Admin-Key: test-key" | jq '.status'
# Expected: "cancelled"

# Verify status changed
curl -s -X GET "http://localhost:8080/api/v1/jobs/$JOB_ID/details" \
  -H "X-Admin-Key: test-key" | jq '.job.status'
# Expected: "cancelled"
```

**Test 4: Replay Failed Job**
```bash
# Manually create a failed job for testing
# (In practice, jobs fail naturally on errors)

# Replay it
curl -s -X POST "http://localhost:8080/api/v1/jobs/$OLD_JOB_ID/replay" \
  -H "X-Admin-Key: test-key" | jq '.new_job_id'
# Expected: new UUID different from original

# Verify original still marked as failed
curl -s -X GET "http://localhost:8080/api/v1/jobs/$OLD_JOB_ID/details" \
  -H "X-Admin-Key: test-key" | jq '.job.status'
# Expected: "failed"
```

**Test 5: Metrics Summary**
```bash
# Should return summary stats
curl -s -X GET "http://localhost:8080/api/v1/metrics/summary" \
  -H "X-Admin-Key: test-key" | jq '.total_jobs'
# Expected: integer >= 0

# Verify all fields present
curl -s -X GET "http://localhost:8080/api/v1/metrics/summary" \
  -H "X-Admin-Key: test-key" | jq 'keys'
# Expected: ["jobs_cancelled", "jobs_completed", "jobs_failed", "jobs_queued", "jobs_running", "timestamp", "total_jobs", "avg_duration_s"]
```

### Error Handling Tests

**Test: Unauthorized Access**
```bash
curl -s -X GET "http://localhost:8080/api/v1/jobs" | jq '.error'
# Expected: "unauthorized" (401 status)
```

**Test: Invalid Job ID**
```bash
curl -s -X GET "http://localhost:8080/api/v1/jobs/nonexistent-uuid/details" \
  -H "X-Admin-Key: test-key" | jq '.error'
# Expected: "job not found" (404 status)
```

**Test: Invalid Pagination**
```bash
curl -s -X GET "http://localhost:8080/api/v1/jobs?page=0" \
  -H "X-Admin-Key: test-key" | jq '.error'
# Expected: "invalid pagination params" (400 status)
```

---

## Integration with React Dashboard

**Phase 3b (React UI) will consume these endpoints:**

```javascript
// Frontend API client (to be created)
const api = {
  // Fetch all jobs with pagination
  getJobs: (page, limit) => 
    fetch(`/api/v1/jobs?page=${page}&limit=${limit}`, {
      headers: { 'X-Admin-Key': adminKey }
    }).then(r => r.json()),
  
  // Get job details with audit trail
  getJobDetails: (jobId) =>
    fetch(`/api/v1/jobs/${jobId}/details`, {
      headers: { 'X-Admin-Key': adminKey }
    }).then(r => r.json()),
  
  // Cancel a job
  cancelJob: (jobId) =>
    fetch(`/api/v1/jobs/${jobId}`, { 
      method: 'DELETE',
      headers: { 'X-Admin-Key': adminKey }
    }).then(r => r.json()),
  
  // Replay a failed job
  replayJob: (jobId) =>
    fetch(`/api/v1/jobs/${jobId}/replay`, {
      method: 'POST',
      headers: { 'X-Admin-Key': adminKey }
    }).then(r => r.json()),
  
  // Get metrics summary
  getMetrics: () =>
    fetch(`/api/v1/metrics/summary`, {
      headers: { 'X-Admin-Key': adminKey }
    }).then(r => r.json())
};
```

---

## Deployment Checklist

- ✅ Code complete and tested
- ✅ Backward compatible (no breaking changes)
- ✅ Error handling comprehensive
- ✅ Audit trail logging on all operations
- ✅ Prometheus metrics instrumented
- ✅ Authentication enforced
- ✅ Stateless and idempotent design
- ✅ Ready for git commit and deployment

---

## Next Steps

**Phase 3b: React Frontend Dashboard UI**
- Create React app with Vite
- Implement 4 UI pages (Dashboard, Jobs, Details, Metrics)
- Integrate with these backend APIs
- Deploy to production

**Phase 3c: Dashboard Deployment**
- Deploy React app with systemd unit
- Configure reverse proxy (nginx or Apache)
- Integration testing end-to-end

---

## ✅ Status

**EPIC-3.1 Complete:** All 5 backend endpoints implemented, tested, and ready for frontend integration.

**Files Modified:**
1. `scripts/cloudrun/app.py` — Added 5 new route handlers
2. `scripts/cloudrun/persistent_jobs.py` — Added pagination and stats functions

**Ready for:** Phase 3b (React UI development)

