# DAY 2: KAFKA & PROTOBUF GENERATION — EXECUTION CHECKLIST
**Date**: March 12, 2026  
**Duration**: 30 minutes  
**Owner**: Platform Operator  
**Prerequisite**: Day 1 MUST BE COMPLETE  
**Status**: ✅ Ready for Execution

---

## PRE-EXECUTION CHECKLIST (5 minutes)

Before starting Day 2:

- [ ] Day 1 PostgreSQL deployment completed and verified
- [ ] All 8 migrations applied successfully
- [ ] Database health check passed
- [ ] You have read [DAY1_POSTGRESQL_EXECUTION_PLAN.md](DAY1_POSTGRESQL_EXECUTION_PLAN.md)
- [ ] Git repository is up-to-date: `git pull origin main`
- [ ] Protocol Buffer compiler installed: `protoc --version` (3.12+)
- [ ] Go installed (1.24+): `go version`
- [ ] Python 3 installed: `python3 --version`

---

## WHAT THIS DOES

**Scope**: Deploy Kafka message broker and generate gRPC protobuf artifacts

**Components**:
1. **Kafka Broker**: Message queue for async processing
   - 4 topics: discovery.raw, discovery.normalized, compliance.events, metrics
   - Persistence: JSONL write-once logs in S3

2. **Protobuf Compilation**: Generate language bindings
   - Python: `nexus-engine/proto/gen/python/nexus/pb2.py`
   - Go: `nexus-engine/proto/gen/go/pb/`
   - Node.js: `nexus-engine/proto/gen/js/`

**Success Indicator**: Kafka running on localhost:9092, 4 topics created, proto files in `proto/gen/`.

---

## STEP-BY-STEP EXECUTION

### Step 1: Verify Day 1 Is Complete (5 minutes)

Before starting Kafka deployment, confirm the database is ready:

```bash
# Connect to database
psql -h localhost -U postgres -d nexus_engine

# Run a simple query
SELECT 1;

# Check migration history (must be 8)
SELECT COUNT(*) FROM public.db_version;
```

**Expected Output**: `count: 8`

If not, **STOP** and fix Day 1 before proceeding.

---

### Step 2: Run the Day 2 Script (20 minutes)

```bash
cd /home/akushnir/self-hosted-runner

# Run the script and log output
bash nexus-engine/scripts/day2_kafka_protos.sh 2>&1 | tee logs/day2-execution.log

# In another terminal, monitor progress
tail -f logs/day2-execution.log
```

**What's Happening**:
1. Checks for Kafka prerequisites (docker/java)
2. Pulls Kafka image and starts broker
3. Waits for broker to be ready (bootstrap completed)
4. Creates 4 topics with proper retention/partitioning
5. Compiles `.proto` files using `protoc`
6. Generates language-specific bindings (Python, Go, Node)
7. Validates all generated files

**Progress Milestones**:
```
✅ Kafka broker starting...
✅ Waiting for broker readiness (can take 10-15 seconds)...
✅ Broker ready on localhost:9092
✅ Creating topic: nexus.discovery.raw (3 partitions, 1 replica)
✅ Creating topic: nexus.discovery.normalized (3 partitions, 1 replica)
✅ Creating topic: nexus.compliance.events (1 partition)
✅ Creating topic: nexus.metrics (5 partitions, 1 replica)
✅ Compiling protos: nexus/v1/discovery.proto
✅ Generated: nexus-engine/proto/gen/python/
✅ Generated: nexus-engine/proto/gen/go/
✅ Generated: nexus-engine/proto/gen/js/
✅ Validation: All proto bindings generated successfully
```

---

### Step 3: Verify Success (5 minutes)

After the script completes, verify all components:

```bash
# 1. Check Kafka is running
docker ps | grep kafka

# Expected: Container running, port 9092 exposed

# 2. List created topics
docker exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --list

# Expected:
#   __consumer_offsets
#   nexus.compliance.events
#   nexus.discovery.normalized
#   nexus.discovery.raw
#   nexus.metrics

# 3. Check topic details
docker exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --describe --topic nexus.discovery.raw

# Expected: Topic with 3 partitions, replication factor 1

# 4. Verify proto files were generated
ls -lh nexus-engine/proto/gen/

# Expected: python/, go/, js/ directories with generated files

# 5. Verify Python protos specifically
python3 -c "import sys; sys.path.insert(0, 'nexus-engine/proto/gen/python'); \
  from nexus.v1 import discovery_pb2; print('✅ Python proto imports OK')"

# 6. Verify Go protos (optional, if Go is available)
ls -la nexus-engine/proto/gen/go/pb/*.pb.go | head -5
```

**All checks pass?** ✅ Day 2 is COMPLETE. Proceed to Day 3.

---

## TROUBLESHOOTING

### Error: "Kafka broker not responding after 30 seconds"

**Cause**: Kafka container not starting or slow start

**Fix**:
```bash
# Check Docker container logs
docker logs kafka

# Check if port 9092 is already in use
lsof -i :9092 || echo "Port is free"

# Forcefully restart Kafka
docker stop kafka && docker rm kafka
sleep 5
bash nexus-engine/scripts/day2_kafka_protos.sh
```

### Error: "Topic creation failed: connection timeout"

**Cause**: Kafka broker not fully initialized yet

**Fix** (Retry Logic — built-in):
```bash
# The script has automatic retry (3 attempts, 5-second delay)
# Just wait and let it retry

# If retries exhaust, check broker status:
docker exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092
```

### Error: "protoc command not found"

**Cause**: Protocol Buffer compiler not installed

**Fix**:
```bash
# Install protoc (depends on OS)

# macOS
brew install protobuf

# Ubuntu/Debian
sudo apt-get install protobuf-compiler

# CentOS/RHEL
sudo yum install protobuf-compiler

# Verify installation
protoc --version
```

### Error: "Python import fails for proto files"

**Cause**: Missing `__init__.py` files or path issues

**Fix**:
```bash
# Check directory structure
find nexus-engine/proto/gen/python -type f | head -10

# Create __init__.py files if missing
touch nexus-engine/proto/gen/python/__init__.py
touch nexus-engine/proto/gen/python/nexus/__init__.py

# Re-run the script to regenerate
bash nexus-engine/scripts/day2_kafka_protos.sh
```

### Error: "Port 9092 already in use" (from previous Kafka instance)

**Cause**: Container from a previous run still occupies the port

**Fix**:
```bash
# Find and remove old Kafka container
docker ps -a | grep kafka
docker rm -f <container-id>

# Verify port is free
lsof -i :9092 || echo "✅ Port 9092 is now free"

# Re-run the script
bash nexus-engine/scripts/day2_kafka_protos.sh
```

---

## WHAT'S NEXT

After verification succeeds:

1. **Checkpoint**: Day 2 Complete ✅
2. **Notify**: Day 3 can now start
3. **Handoff**: Move to [DAY3_NORMALIZER_CRONJOB_CHECKLIST.md](DAY3_NORMALIZER_CRONJOB_CHECKLIST.md)
4. **Command**: `bash scripts/deploy/apply_cronjob_and_test.sh`

---

## REFERENCE INFORMATION

### Kafka Topic Configuration

| Topic | Partitions | Retention | Purpose |
|-------|-----------|-----------|---------|
| `nexus.discovery.raw` | 3 | 7 days | Raw GitHub metadata |
| `nexus.discovery.normalized` | 3 | 7 days | Cleaned/enriched metadata |
| `nexus.compliance.events` | 1 | 30 days | Compliance audit events |
| `nexus.metrics` | 5 | 1 day | Performance metrics (high volume) |

### Protobuf Message Structure

```protobuf
package nexus.v1;

message Repository {
  string id = 1;
  string owner = 2;
  string name = 3;
  repeated string topics = 4;
  int64 created_at = 5;
  int64 updated_at = 6;
}

message DiscoveryEvent {
  Repository repository = 1;
  string event_type = 2;  // created, updated, deleted
  int64 timestamp = 3;
}
```

### Generated File Structure

```
nexus-engine/proto/gen/
├── python/
│   ├── __init__.py
│   └── nexus/
│       ├── __init__.py
│       └── v1/
│           ├── __init__.py
│           ├── discovery_pb2.py
│           ├── discovery_pb2_grpc.py
│           └── ...
├── go/
│   └── pb/
│       ├── discovery.pb.go
│       ├── discovery_grpc.pb.go
│       └── ...
└── js/
    ├── nexus/
    │   └── v1/
    │       ├── discovery_pb.js
    │       ├── discovery_grpc_pb.js
    │       └── ...
```

---

## GOVERNANCE VERIFICATION

After Day 2 completes, verify:

- ✅ **Immutable**: Kafka logs stored in S3 with Object Lock (write-once)
- ✅ **Ephemeral**: No credentials in Docker/Kubernetes configs
- ✅ **Idempotent**: Proto compilation is deterministic (same output)
- ✅ **No-Ops**: Fully automated script (0 manual steps)
- ✅ **Hands-Off**: Broker config via environment variables
- ✅ **Logged**: Full execution logged to `logs/day2-execution.log`

---

## SUCCESS METRICS

| Metric | Expected | How to Verify |
|--------|----------|---------------|
| Kafka Running | ✅ | `docker ps \| grep kafka` |
| Topics Created | 4 | `kafka-topics --list` |
| Proto Files Generated | All 3 langs | `ls -la nexus-engine/proto/gen/` |
| Python Import OK | ✅ | `python3 -c "from nexus.v1 import discovery_pb2"` |

---

**Time Estimate**: 30 minutes  
**Complexity**: Medium (Kafka + Protobuf)  
**Risk**: MEDIUM (Kafka takes time to start; protoc failures are exceptional)  
**Success Rate**: 90%+ (assuming prerequisites met)

---

**Ready?** Run the script and let it execute. Total time: ~30 minutes.  
**Questions?** See "Troubleshooting" above or contact Platform team.
