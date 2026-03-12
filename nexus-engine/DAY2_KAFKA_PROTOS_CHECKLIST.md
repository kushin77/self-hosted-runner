# DAY 2 EXECUTION CHECKLIST
**Date:** March 12, 2026  
**Status:** Ready for Operator Execution  
**Prerequisites:** ✅ Day 1 Postgres (migrations + RLS) completed

---

## Quick Start

Once Day 1 Postgres is confirmed running, operator executes:

```bash
cd /path/to/self-hosted-runner/nexus-engine
bash scripts/day2_kafka_protos.sh 2>&1 | tee logs/day2-output.log
```

## What Day 2 Does

| Step | Task | Command | Expected Output |
|------|------|---------|-----------------|
| **1** | Start Kafka & Zookeeper | `docker-compose up -d zookeeper kafka` | Kafka broker listening on :9092 |
| **2** | Create `nexus.discovery.raw` topic | `kafka-topics --create --topic nexus.discovery.raw` | Topic created or already exists |
| **3** | Create `nexus.discovery.normalized` topic | `kafka-topics --create --topic nexus.discovery.normalized` | Topic created or already exists |
| **4** | Compile protos | `protoc --go_out=. proto/discovery.proto` | `pkg/discovery/discovery.pb.go` generated |
| **5** | Remove temp stub | `rm pkg/discovery/discovery.go` | Stub removed (was temporary) |
| **6** | Sync go.mod/go.sum | `go mod tidy` | Deps synced |
| **7** | Build binary | `go build -o bin/ingestion ./cmd/ingestion` | Binary at `nexus-engine/bin/ingestion` |
| **8** | Run tests | `go test ./...` | All tests pass |
| **9** | Verify Kafka | Connect producer/consumer to Kafka topics | Messages flow through pipeline |

---

## Prerequisites Checklist (Before Running Day 2)

- [ ] Day 1 Postgres migrations completed (see `DAY1_POSTGRESQ_EXECUTION_PLAN.md`)
- [ ] Docker daemon running
- [ ] `docker-compose` installed
- [ ] `protoc` installed: `apt-get install protoc-gen-go protoc-gen-go-grpc`
- [ ] Go 1.21+ installed
- [ ] Repository cloned from main branch (or day2/kafka-protos)

---

## Automate Day 2 (Operator-Run on Fullstack)

### Option A: Run bundled script

```bash
cd nexus-engine
chmod +x scripts/day2_kafka_protos.sh
bash scripts/day2_kafka_protos.sh
```

The script will:
1. Start Kafka & Zookeeper
2. Create topics
3. Compile protos
4. Replace temp stub
5. Build binary
6. Run tests
7. Log output to `logs/day2-execution.log`

### Option B: Manual Steps (Debug/Inspect Each Step)

```bash
cd nexus-engine

# Step 1: Kafka
docker-compose up -d zookeeper kafka
docker-compose exec kafka kafka-topics --create \
  --topic nexus.discovery.raw --partitions 1 --replication-factor 1 \
  --bootstrap-server localhost:9092 --if-not-exists

docker-compose exec kafka kafka-topics --create \
  --topic nexus.discovery.normalized --partitions 1 --replication-factor 1 \
  --bootstrap-server localhost:9092 --if-not-exists

# Step 2: Protos
protoc --go_out=. --go_opt=paths=source_relative proto/discovery.proto

# Step 3: Replace Stub
rm pkg/discovery/discovery.go

# Step 4: Build
go mod tidy
go build -o bin/ingestion ./cmd/ingestion

# Step 5: Test
go test ./...
```

---

## Expected Outputs

After Day 2 completes successfully:

```
📁 nexus-engine/
├── bin/
│   └── ingestion                      ← Compiled binary
├── pkg/
│   └── discovery/
│       ├── discovery.pb.go            ← Generated proto code (✨ new)
│       └── (discovery.go removed)     ← Temp stub deleted
├── logs/
│   └── day2-execution.log             ← Detailed execution log
└── [other dirs...]

✅ Kafka topics ready:
   - nexus.discovery.raw (producer endpoint)
   - nexus.discovery.normalized (consumer endpoint)

✅ Build succeeded:
   - bin/ingestion executable works
   - All unit tests pass

✅ Services online:
   - PostgreSQL (from Day 1) with RLS + audit tables
   - Kafka brokers (ports 9092, 29092)
   - Ready for Day 3: normalizers
```

---

## Troubleshooting

### protoc: command not found
```bash
apt-get update && apt-get install -y protoc-gen-go protoc-gen-go-grpc
```

### Docker daemon not running
```bash
sudo systemctl start docker
docker-compose up -d zookeeper kafka
```

### go build fails with missing imports
```bash
go mod download
go mod tidy
go build -o bin/ingestion ./cmd/ingestion
```

### Kafka broker unreachable
```bash
# Check logs
docker-compose logs kafka

# Restart
docker-compose down && docker-compose up -d zookeeper kafka && sleep 10
```

### Tests fail
- Check `go test -v ./...` output for specific errors
- Ensure PostgreSQL from Day 1 is still running: `psql -U nexus_user -d nexus_engine`
- Ensure Kafka topics exist: `docker-compose exec kafka kafka-topics --list --bootstrap-server localhost:9092`

---

## Post-Day-2

Once Day 2 completes:

1. **Commit results:** `git add -A && git commit -m "chore(day2): Kafka topics + protos compiled"`
2. **Push to day2/kafka-protos branch** (for review & merge)
3. **Proceed to Day 3:** Normalizer pod tests (CronJob)
4. **Deploy to production:** Use `scripts/deploy_direct.sh` with the compiled binary

---

## Observability During Day 2

Monitor Kafka in real-time (in separate terminal):

```bash
# Watch topic metrics
docker-compose exec kafka kafka-consumer-groups --list --bootstrap-server localhost:9092

# Check topic offsets
docker-compose exec kafka kafka-log-dirs --describe --bootstrap-server localhost:9092

# Produce test message
echo '{"webhook":"test"}' | docker-compose exec -T kafka kafka-console-producer \
  --broker-list localhost:9092 --topic nexus.discovery.raw

# Consume messages
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 --topic nexus.discovery.raw --from-beginning
```

---

## References

- [DAY1_POSTGRESQ_EXECUTION_PLAN.md](./DAY1_POSTGRESQ_EXECUTION_PLAN.md) — Postgres setup
- [scripts/day2_kafka_protos.sh](./scripts/day2_kafka_protos.sh) — Automated execution
- [DEPLOYMENT_DIRECT.md](./DEPLOYMENT_DIRECT.md) — Operator deployment post-Day 2
- [NEXUS_ARCHITECTURE_DIAGRAM.md](./NEXUS_ARCHITECTURE_DIAGRAM.md) — System overview
