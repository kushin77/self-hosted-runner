# NEXUS Ops Portal

Real-time observability dashboard for the NEXUS discovery pipeline.

## Quick Start

```bash
cd portal
npm install
npm run dev
```

Portal will be available at `http://localhost:3000`.

**API Proxy**: Dev server proxies `/api/*` to `http://localhost:8080` (configurable via `NEXUS_API_URL` env var).

## For Production

```bash
npm run build  # Creates dist/
docker build -t nexus-ops-portal:latest .
docker push gcr.io/my-project/nexus-ops-portal:latest
```

Deploy to Cloud Run:
```bash
gcloud run deploy nexus-ops-portal \
  --image gcr.io/my-project/nexus-ops-portal:latest \
  --set-env-vars="NEXUS_API_URL=http://nexus-ingestion:8080"
```

## Features

- 📊 **Dashboard**: System health, queue depth, producer rate
- 📡 **Kafka Metrics**: Topic lag, queue monitoring
- ⚙️ **Normalizer Jobs**: Job status, event counts, error tracking
- 📋 **Audit Logs**: JSONL log viewer with filtering and export

## Architecture

Extracts observable metrics from:
- **Kafka Brokers**: Queue depth, consumer lag, producer throughput
- **PostgreSQL**: Audit logs (immutable JSONL)
- **Kubernetes**: CronJob status (normalizer pod lifecycle)

See [NEXUS_OPS_PORTAL.md](../NEXUS_OPS_PORTAL.md) for design details.

## API Endpoints

All proxied to NEXUS backend:

- `GET /api/health` — System health status
- `GET /api/kafka/metrics` — Kafka topic metrics
- `GET /api/normalizer/jobs` — Normalizer job status
- `GET /api/audit/logs?limit=100&offset=0` — Audit log stream
- `POST /api/normalizer/trigger` — Manual normalizer trigger (admin)
