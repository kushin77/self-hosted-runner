# NexusShield Portal - API Documentation

**Version:** v1  
**Status:** Production MVP  
**Last Updated:** March 12, 2026

---

## Base URL

```
http://localhost:5000/api/v1
```

## Authentication

Currently using implicit trust model. Future versions will support:
- JWT tokens
- OAuth2
- RBAC

## Response Format

All API responses follow a standardized format:

```json
{
  "success": true,
  "data": {},
  "error": null,
  "metadata": {
    "timestamp": "2026-03-12T10:00:00Z",
    "requestId": "req-123456",
    "version": "v1"
  }
}
```

---

## Endpoints

### Products

#### List Products

```
GET /products
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "ops",
      "name": "NexusShield OPS",
      "status": "active",
      "version": "1.0.0",
      "features": ["deployment", "secrets", "observability"]
    }
  ]
}
```

---

### OPS Product

#### Deployments

##### List All Deployments

```
GET /ops/deployments
```

**Query Parameters:**
- `environment`: Filter by environment (development, staging, production)
- `status`: Filter by status (pending, running, success, failed)
- `limit`: Records per page (default: 20)
- `offset`: Pagination offset (default: 0)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "deploy-001",
      "name": "Backend Service v1.2.3",
      "environment": "production",
      "status": "success",
      "version": "v1.2.3",
      "startTime": "2026-03-12T07:00:00Z",
      "endTime": "2026-03-12T07:10:00Z",
      "duration": 600,
      "deployedBy": "github-actions",
      "metadata": {
        "cluster": "gke-prod-us-east1"
      }
    }
  ]
}
```

##### Get Deployment Details

```
GET /ops/deployments/:id
```

**Response:** Single deployment object (see above)

##### Create Deployment

```
POST /ops/deployments
```

**Request Body:**
```json
{
  "name": "New Service",
  "environment": "staging",
  "version": "v0.1.0"
}
```

#### Secrets

##### List Secrets

```
GET /ops/secrets
```

**Query Parameters:**
- `type`: Filter by type (database, api-key, certificate, token)
- `status`: Filter by status (active, rotating, expired)

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "secret-db-001",
      "name": "primary-db-credentials",
      "type": "database",
      "status": "active",
      "expiresAt": "2026-05-11T00:00:00Z",
      "rotationPolicy": {
        "enabled": true,
        "interval": 90,
        "lastRotated": "2026-02-10T00:00:00Z"
      }
    }
  ]
}
```

##### Rotate Secret

```
POST /ops/secrets/:id/rotate
```

**Response:**
```json
{
  "success": true,
  "data": {
    "id": "secret-db-001",
    "status": "rotating",
    "rotatedAt": "2026-03-12T10:00:00Z"
  }
}
```

#### Observability

##### Get Service Status

```
GET /ops/observability/status
```

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "name": "backend-api",
      "status": "healthy",
      "uptime": 99.98,
      "latency": 45,
      "lastCheck": "2026-03-12T10:00:00Z",
      "metrics": {
        "requestsPerSecond": 1250,
        "errorRate": 0.02
      }
    }
  ]
}
```

---

### Diagrams (Future)

#### Generate Failure Analysis Diagram

```
POST /diagrams/analyze-failure
```

**Request Body:**
```json
{
  "failures": [
    {
      "service": "backend-api",
      "errorMessage": "Connection timeout",
      "timestamp": "2026-03-12T10:00:00Z"
    }
  ]
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "diagramId": "diag-123",
    "diagram": {
      "nodes": [],
      "edges": []
    },
    "rootCauseAnalysis": {
      "suspectedService": "backend-api",
      "confidence": 0.95,
      "factors": []
    },
    "recommendations": []
  }
}
```

---

## Error Handling

Errors include a `code` and `message`:

```json
{
  "success": false,
  "error": {
    "code": "NOT_FOUND",
    "message": "Resource not found",
    "details": {}
  }
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|------------|-------------|
| NOT_FOUND | 404 | Resource does not exist |
| INVALID_REQUEST | 400 | Invalid request parameters |
| UNAUTHORIZED | 401 | Authentication required |
| PERMISSION_DENIED | 403 | Authorization failed |
| INTERNAL_ERROR | 500 | Server error |

---

## Rate Limiting

Currently unlimited. Future versions will implement rate limiting per user/IP.

---

## Pagination

List endpoints support pagination:

```
GET /ops/deployments?limit=20&offset=0
```

Response includes:
```json
{
  "data": [],
  "total": 150,
  "limit": 20,
  "offset": 0,
  "hasMore": true
}
```

---

## Examples

### Curl

```bash
# Get all deployments
curl http://localhost:5000/api/v1/ops/deployments

# Get specific deployment
curl http://localhost:5000/api/v1/ops/deployments/deploy-001

# Create new deployment
curl -X POST http://localhost:5000/api/v1/ops/deployments \
  -H "Content-Type: application/json" \
  -d '{"name":"NewService","environment":"staging","version":"v0.1.0"}'
```

### JavaScript/Fetch

```javascript
// Get deployments
const response = await fetch('http://localhost:5000/api/v1/ops/deployments')
const { data } = await response.json()

// Create deployment
const result = await fetch('http://localhost:5000/api/v1/ops/deployments', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    name: 'NewService',
    environment: 'staging',
    version: 'v0.1.0'
  })
})
```

---

## Webhooks (Future)

Coming soon: Event-based webhooks for automation

---

## Changelog

### v1.0.0 (2026-03-12)
- Initial release
- Products endpoint
- OPS deployments, secrets, observability
- Diagram engine foundation

---

## Support

For issues or questions:
1. Check the documentation
2. Review error messages
3. Check logs at `http://localhost:5000/logs`
4. Open GitHub issue
