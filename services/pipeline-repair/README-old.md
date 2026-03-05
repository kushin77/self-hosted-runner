Autonomous Pipeline Repair Service (MVP)

Usage

Start the HTTP API (defaults to port 8081):

```bash
cd services/pipeline-repair
npm install
node lib/server.js
```

Analyze a failure event (example):

```bash
curl -s -X POST http://localhost:8081/analyze \
  -H 'Content-Type: application/json' \
  -d '{"id":"evt-1","errorMessage":"Error: Connection timeout after 30s","attemptNumber":1}'
```

The service returns a JSON recommendation describing the repair action, confidence, and whether manual approval is required.
