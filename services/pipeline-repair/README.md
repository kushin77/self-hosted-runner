# Autonomous Pipeline Repair Service (MVP)

Implements an autonomous repair engine that detects pipeline failures and recommends or executes corrective actions with approval gating for medium/high-risk repairs.

## Features

### Repair Strategies
- **Retry with backoff**: Detects transient failures (timeouts, connection resets, socket hangups) and recommends exponential backoff retry
- **Timeout increase**: Safely increases timeout values when operations exceed limits
- Extensible strategy framework for custom repair primitives

### Safety & Governance
- **Risk assessment**: Automatically classifies repairs as LOW, MEDIUM, or HIGH risk
- **Approval gating**: Medium/high-risk repairs require explicit human approval before execution
- **Audit trail**: Immutable logs of all repair decisions and approvals
- **Approval tracking**: Persistent approval requests with expiration and status

## Architecture

```
┌─────────────────┐
│ Pipeline Event  │
└────────┬────────┘
         │
         ▼
    ┌─────────────────────┐
    │ RepairService       │
    │ ┌─────────────────┐ │
    │ │ Analyze         │ │
    │ │ ├─ RetryStrategy   │
    │ │ └─ TimeoutIncr. │ │
    │ │                 │ │
    │ └─────────────────┘ │
    └─────┬───────┬───────┘
          │       │
    ┌─────▼──┐  ┌─▼──────────────┐
    │ AuditLog│  │ ApprovalEngine │
    └────────┘  └─┬──────────────┘
                  │
         ┌────────┴─────────┐
         │ Auto-execute     │
         │ or wait approval │
         └──────────────────┘
```

## API Endpoints

### GET /health
Health check endpoint.

**Response:**
```json
{ "status": "ok" }
```

### POST /analyze
Analyze a failure event and identify repair strategies.

**Request:**
```json
{
  "id": "evt-1234",
  "errorMessage": "Error: Connection timeout after 30s",
  "attemptNumber": 1
}
```

**Response:**
```json
{
  "status": "REPAIR_IDENTIFIED",
  "confidence": 0.8,
  "recommendedAction": "RETRY",
  "strategy": "retry-strategy",
  "risk": "LOW",
  "parameters": { "delayMs": 2000, "attempt": 2 },
  "requiresApproval": false,
  "recommendation": { ... }
}
```

### POST /approve
Approve a pending repair request.

**Request:**
```json
{
  "eventId": "evt-1234",
  "approver": "engineering-oncall",
  "reason": "Approved for production traffic"
}
```

**Response:**
```json
{
  "decision": "APPROVED",
  "approver": "engineering-oncall",
  "reason": "Approved for production traffic",
  "timestamp": "2026-03-05T17:30:00Z",
  "riskLevel": "MEDIUM"
}
```

### POST /reject
Reject a pending repair request.

**Request:**
```json
{
  "eventId": "evt-1234",
  "rejector": "security-ops",
  "reason": "Requires manual investigation first"
}
```

### GET /approval-status/:eventId
Check approval status for an event.

**Response:**
```json
{
  "eventId": "evt-1234",
  "status": "APPROVED",
  "approvals": 1,
  "rejections": 0,
  "expiresAt": "2026-03-06T17:30:00Z",
  "action": { "action": "RETRY", "risk": "LOW" }
}
```

### POST /execute
Execute an approved repair action.

**Request:**
```json
{
  "eventId": "evt-1234",
  "approvalId": "apr-evt-1234-1234567890"
}
```

**Response:**
```json
{
  "status": "REPAIR_EXECUTED",
  "eventId": "evt-1234",
  "executedAt": "2026-03-05T17:30:00Z",
  "message": "Repair action executed"
}
```

### GET /strategies
List available repair strategies.

**Response:**
```json
{
  "strategies": [
    { "name": "retry-strategy", "class": "RetryStrategy" },
    { "name": "timeout-increase-strategy", "class": "TimeoutIncreaseStrategy" }
  ]
}
```

## Getting Started

### Start the HTTP API (defaults to port 8081):

```bash
cd services/pipeline-repair
npm install
node lib/server.js
```

### Database migrations (Postgres)

The service supports Postgres migrations via `node-pg-migrate`.

Set `REPAIR_DB=postgres` and `REPAIR_PG_CONN` to your Postgres connection string.

Run migrations from the repository root:

```bash
cd services/pipeline-repair
npx node-pg-migrate up --migrations-dir ./migrations
```

To rollback:

```bash
npx node-pg-migrate down --migrations-dir ./migrations
```


### Run tests

```bash
# Unit tests
bash tests/unit.sh

# Integration tests
bash tests/integration-test.sh

# Manual verification
PORT=8082 node lib/server.js &
bash tests/verify-http.sh
kill $!
```

### Example: Full repair workflow

```bash
# 1. Report a failure event
EVENT_ID=$(uuidgen)
RESULT=$(curl -s -X POST http://localhost:8081/analyze \
  -H 'Content-Type: application/json' \
  -d "{
    \"id\": \"$EVENT_ID\",
    \"errorMessage\": \"Error: Request timeout after 5000ms\",
    \"attemptNumber\": 1
  }")
echo "$RESULT" | jq .

# 2. If approval needed, check status
curl -s http://localhost:8081/approval-status/$EVENT_ID | jq .

# 3. Approve the repair
curl -s -X POST http://localhost:8081/approve \
  -H 'Content-Type: application/json' \
  -d "{
    \"eventId\": \"$EVENT_ID\",
    \"approver\": \"oncall@company.com\"
  }" | jq .

# 4. Execute the repair
curl -s -X POST http://localhost:8081/execute \
  -H 'Content-Type: application/json' \
  -d "{ \"eventId\": \"$EVENT_ID\" }" | jq .
```

## Configuration

### Persistence & Data Storage

Approvals and repair proposals are persisted for audit trails and recovery.

#### Approvals Storage (JSON or SQLite)
- **Default**: JSON file-based approvals stored at `services/data/approvals.json` (or configured via `REPAIR_DATA_DIR`)
- **Mode**: Read on startup; atomic writes with mode 0600 (owner read/write only)
- **Location**: Configurable via env var `REPAIR_DATA_DIR` (defaults to `./data` relative to service)
- **SQLite optional**: If `sqlite3` is installed, future versions may auto-migrate to SQLite backend

#### Repair Proposals (NDJSON)
- Repair proposals persisted to `services/pipeline-repair/data/repair-proposals.ndjson`
- Each line is a JSON object (newline-delimited JSON format)
- Useful for audit/telemetry and recovery after service restart

### Environment Variables

- `PORT`: HTTP API listen port (default: `8081`)
- `REPAIR_APPROVAL_THRESHOLD`: Risk threshold for approval gating [0.0–1.0] (default: `0.7`)
- `REPAIR_DATA_DIR`: Directory for JSON approvals storage (default: `./data` relative to service)
- `APPROVAL_SLACK_WEBHOOK`: Slack incoming webhook URL for approval notifications (optional)
- `REPAIR_DB`: Postgres adapter selection (set to `postgres` to use Postgres; defaults to NDJSON fallback)
- `REPAIR_PG_CONN`: Postgres connection string (required if `REPAIR_DB=postgres`)
- `REPAIR_USE_DB`: Set to `true` to prefer durable DB storage if available (default: `false`)
- `ADMIN_API_KEY`: API key for `/approve` endpoint; if set, requests must include `X-API-Key` header

### Examples

**Start with Slack notifications:**
```bash
export APPROVAL_SLACK_WEBHOOK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
export PORT=8082
node lib/server.js
```

**Use Postgres for audit**:
```bash
export REPAIR_DB=postgres
export REPAIR_PG_CONN=postgresql://user:pass@localhost:5432/repair_db
export REPAIR_USE_DB=true
npx node-pg-migrate up
node lib/server.js
```

## MVP Acceptance Criteria

- ✅ Detect and classify transient failures
- ✅ Recommend appropriate repair strategies (Retry, Timeout adjustment)
- ✅ Risk-based approval gating (LOW/MEDIUM/HIGH)
- ✅ Audit trail for all repair decisions and approvals
- ✅ HTTP API for failure reporting and repair execution
- ✅ Unit and integration test coverage
- ✅ Approvals persistence (JSON-backed with optional Slack notifications)

## Future Enhancements

- [ ] Database persistence for audit logs and approvals
- [ ] Slack/email notifications for approval requests
- [ ] Webhook integrations for CI/CD pipeline execution
- [ ] Machine learning-based failure classification
- [ ] Custom repair strategies per pipeline/namespace
- [ ] SLA-based auto-escalation for delayed approvals
- [ ] Repair success/failure rate tracking
- [ ] Integration with incident management systems (PagerDuty, Datadog)
- [ ] Repair history and rollback capabilities
