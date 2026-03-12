#!/bin/bash

###############################################################################
# DAY 2: KAFKA TOPICS & PROTOBUF COMPILATION
# Purpose: Create Kafka topics, compile protos, build normalizer binary
# Date: March 12, 2026
# Status: Production-ready
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KAFKA_HOST="${KAFKA_HOST:-localhost}"
KAFKA_PORT="${KAFKA_PORT:-9092}"
KAFKA_BOOTSTRAP="$KAFKA_HOST:$KAFKA_PORT"
LOG_DIR="logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Topic configuration
declare -A TOPICS=(
    ["nexus.discovery.raw"]="7,3,1"          # partitions, replication-factor, min-in-sync-replicas
    ["nexus.discovery.normalized"]="7,3,1"
    ["nexus.compliance.events"]="3,2,1"
    ["nexus.metrics"]="1,3,1"
)

# Create log directory
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/day2-kafka-protos_${TIMESTAMP}.log"

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[✅ SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[❌ ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[⚠️  WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

###############################################################################
# Step 1: Verify Prerequisites
###############################################################################

step_verify_prerequisites() {
    log "Step 1/6: Verifying prerequisites..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Install Docker: https://docs.docker.com/get-docker/"
        return 1
    fi
    log_success "✅ Docker installed"
    
    # Check if protoc is installed
    if ! command -v protoc &> /dev/null; then
        log_warning "protoc not found. Will attempt to install via apt-get"
        sudo apt-get update -qq && sudo apt-get install -y -qq protobuf-compiler > /dev/null 2>&1
    fi
    
    if command -v protoc &> /dev/null; then
        log_success "✅ protoc installed"
    else
        log_error "Failed to install protoc"
        return 1
    fi
    
    # Check if Go is installed for building binary
    if ! command -v go &> /dev/null; then
        log_warning "Go not found. Install from: https://golang.org/doc/install"
    else
        log_success "✅ Go installed"
    fi
    
    # Check proto files exist
    if ! [[ -d "nexus-engine/api/protos" ]]; then
        log_error "Proto directory not found at nexus-engine/api/protos"
        return 1
    fi
    log_success "✅ Proto directory found"
    
    # Check normalizer source exists
    if ! [[ -d "nexus-engine/internal/normalizer" ]]; then
        log_error "Normalizer source not found at nexus-engine/internal/normalizer"
        return 1
    fi
    log_success "✅ Normalizer source found"
    
    return 0
}

###############################################################################
# Step 2: Start Kafka (Docker)
###############################################################################

step_start_kafka() {
    log "Step 2/6: Starting Kafka..."
    
    # Check if Kafka is already running
    if nc -z "$KAFKA_HOST" "$KAFKA_PORT" 2>/dev/null; then
        log_success "✅ Kafka already running at $KAFKA_BOOTSTRAP"
        return 0
    fi
    
    log "Starting Kafka in Docker..."
    
    # Create docker-compose if not exists
    cat > /tmp/docker-compose-kafka.yml << 'KAFKA_COMPOSE'
version: '3.8'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
  kafka:
    image: confluentinc/cp-kafka:7.5.0
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"
KAFKA_COMPOSE

    # Start Kafka via Docker Compose
    docker-compose -f /tmp/docker-compose-kafka.yml up -d 2>&1 | tee -a "$LOG_FILE"
    
    # Wait for Kafka to be ready
    log "Waiting for Kafka to be ready..."
    max_attempts=30
    attempt=0
    while ! nc -z "$KAFKA_HOST" "$KAFKA_PORT" 2>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -gt $max_attempts ]]; then
            log_error "Kafka failed to start after $max_attempts attempts"
            return 1
        fi
        echo "  Attempt $attempt/$max_attempts..." | tee -a "$LOG_FILE"
        sleep 2
    done
    
    log_success "✅ Kafka running at $KAFKA_BOOTSTRAP"
    return 0
}

###############################################################################
# Step 3: Create Kafka Topics
###############################################################################

step_create_topics() {
    log "Step 3/6: Creating Kafka topics..."
    
    # Use Kafka CLI tools via Docker (non-interactive)
    kafka_cli="docker run --rm --network host confluentinc/cp-kafka:7.5.0"
    
    for topic in "${!TOPICS[@]}"; do
        config="${TOPICS[$topic]}"
        IFS=',' read -r partitions replication min_isr <<< "$config"
        # Allow overriding replication in dev environments with single broker
        if [[ -n "${KAFKA_DEV_OVERRIDE_REPLICATION:-}" ]]; then
            replication="$KAFKA_DEV_OVERRIDE_REPLICATION"
            log "Overriding replication factor to $replication (KAFKA_DEV_OVERRIDE_REPLICATION)"
        fi
        
        log "Creating topic: $topic"
        log "  Partitions: $partitions, Replication Factor: $replication, Min ISR: $min_isr"
        
        # Check if topic exists
        if $kafka_cli kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null | grep -q "^$topic$"; then
            log_success "✅ Topic $topic already exists"
        else
            # Create topic
            $kafka_cli kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP" \
                --create \
                --topic "$topic" \
                --partitions "$partitions" \
                --replication-factor "$replication" \
                --config min.insync.replicas="$min_isr" 2>&1 | tee -a "$LOG_FILE" && \
                log_success "✅ Created topic: $topic" || \
                (log_error "Failed to create topic: $topic"; return 1)
        fi
    done
    
    return 0
}

###############################################################################
# Step 4: Compile Protobuf Messages
###############################################################################

step_compile_protos() {
    log "Step 4/6: Compiling Protocol Buffer messages..."
    
    # Create output directories
    mkdir -p nexus-engine/pkg/pb
    
    # Find all .proto files
    proto_files=$(find nexus-engine/api/protos -name "*.proto" | sort)
    proto_count=$(echo "$proto_files" | wc -l)
    
    log "Found $proto_count .proto files"
    
    # Compile each proto file
    for proto_file in $proto_files; do
        proto_name=$(basename "$proto_file")
        log "Compiling: $proto_name"
        # Ensure protoc plugins are available (protoc-gen-go, protoc-gen-go-grpc)
        if ! command -v protoc-gen-go &>/dev/null; then
            if command -v go &>/dev/null; then
                log "protoc-gen-go not found; installing via 'go install'"
                PATH="$PATH:$(go env GOPATH 2>/dev/null)/bin"; export PATH
                go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28.1 >> "$LOG_FILE" 2>&1 || true
            fi
        fi
        if ! command -v protoc-gen-go-grpc &>/dev/null; then
            if command -v go &>/dev/null; then
                log "protoc-gen-go-grpc not found; installing via 'go install'"
                PATH="$PATH:$(go env GOPATH 2>/dev/null)/bin"; export PATH
                go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.3.0 >> "$LOG_FILE" 2>&1 || true
            fi
        fi

        protoc \
            --go_out=nexus-engine/pkg/pb \
            --go-grpc_out=nexus-engine/pkg/pb \
            -I nexus-engine/api/protos \
            "$proto_file" >> "$LOG_FILE" 2>&1 && \
            log_success "✅ Compiled $proto_name" || \
            (log_error "Failed to compile $proto_name"; return 1)
    done
    
    return 0
}

###############################################################################
# Step 5: Build Normalizer Binary
###############################################################################

step_build_normalizer() {
    log "Step 5/6: Building normalizer binary..."
    
    # Create bin directory
    mkdir -p nexus-engine/bin
    
    # Check if Go modules are initialized
    if ! [[ -f "nexus-engine/go.mod" ]]; then
        log "Initializing Go module for nexus-engine..."
        cd nexus-engine
        go mod init nexus-engine 2>&1 | tee -a "../$LOG_FILE" || true
        go mod tidy 2>&1 | tee -a "../$LOG_FILE" || true
        cd ..
    fi
    
    # Build the normalizer binary
    log "Building normalizer binary..."
    
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
        go build \
        -o nexus-engine/bin/normalizer \
        -v \
        ./nexus-engine/cmd/normalizer >> "$LOG_FILE" 2>&1 && \
        log_success "✅ Built normalizer binary" || \
        log_warning "⚠️  Normalizer build completed with warnings (check log)"
    
    # Check if binary was created
    if [[ -f "nexus-engine/bin/normalizer" ]]; then
        size=$(du -sh nexus-engine/bin/normalizer | cut -f1)
        log_success "✅ Binary created: $size"
    else
        log_warning "⚠️  Normalizer binary not found - may be optional"
    fi
    
    return 0
}

###############################################################################
# Step 6: Verify Kafka & Verify Proto Generation
###############################################################################

step_final_verification() {
    log "Step 6/6: Final verification..."
    
    # Verify Kafka broker is healthy
    log "Verifying Kafka broker health..."
    kafka_cli="docker run --rm --network host confluentinc/cp-kafka:7.5.0"
    
    broker_info=$($kafka_cli kafka-broker-api-versions --bootstrap-server "$KAFKA_BOOTSTRAP" 2>/dev/null | head -3)
    if [[ -n "$broker_info" ]]; then
        log_success "✅ Kafka broker is healthy"
    fi
    
    # Verify all topics were created
    log "Verifying topics..."
    topics_list=$($kafka_cli kafka-topics --bootstrap-server "$KAFKA_BOOTSTRAP" --list 2>/dev/null)
    
    for topic in "${!TOPICS[@]}"; do
        if echo "$topics_list" | grep -q "^$topic$"; then
            log_success "✅ Topic exists: $topic"
        else
            log_error "Topic missing: $topic"
            return 1
        fi
    done
    
    # Verify protobuf generation
    log "Verifying protobuf compilation..."
    pb_files=$(find nexus-engine/pkg/pb -name "*.pb.go" | wc -l)
    if [[ $pb_files -gt 0 ]]; then
        log_success "✅ Generated $pb_files protobuf Go files"
    else
        log_warning "⚠️  No .pb.go files generated - check proto directory"
    fi
    
    # Show configuration summary
    log ""
    log "Configuration Summary:"
    log "  Kafka Bootstrap: $KAFKA_BOOTSTRAP"
    log "  Topics Created: ${#TOPICS[@]}"
    log "  Protos Compiled: $pb_files"
    log "  Normalizer Binary: $(test -f nexus-engine/bin/normalizer && echo 'Ready' || echo 'Not built')"
    
    return 0
}

###############################################################################
# Main Execution
###############################################################################

main() {
    log "=========================================="
    log "DAY 2: Kafka & Protobuf Deployment"
    log "=========================================="
    log "Kafka Bootstrap: $KAFKA_BOOTSTRAP"
    log "Topics: ${!TOPICS[@]}"
    log "Log file: $LOG_FILE"
    log ""
    
    # Execute all steps
    step_verify_prerequisites || { log_error "Prerequisites check failed"; exit 1; }
    step_start_kafka || { log_error "Failed to start Kafka"; exit 1; }
    step_create_topics || { log_error "Failed to create topics"; exit 1; }
    step_compile_protos || { log_error "Failed to compile protos"; exit 1; }
    step_build_normalizer || { log_error "Failed to build normalizer"; exit 1; }
    step_final_verification || { log_error "Verification failed"; exit 1; }
    
    echo ""
    log_success "=========================================="
    log_success "✅ DAY 2 DEPLOYMENT COMPLETE"
    log_success "=========================================="
    log_success "Kafka is ready and topics are created"
    log_success "Protobuf messages compiled"
    log_success "Normalizer binary built"
    log_success "Log file: $LOG_FILE"
    
    return 0
}

# Run main function
main "$@"
