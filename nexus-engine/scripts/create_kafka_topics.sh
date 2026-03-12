#!/usr/bin/env bash
set -euo pipefail

# Usage: run on fullstack where docker-compose is available
cd "$(dirname "$0")/.." || exit 1

echo "Starting Kafka & Zookeeper containers..."
docker-compose up -d zookeeper kafka
echo "Waiting for Kafka to be available..."
sleep 8

KAFKA_CONTAINER=$(docker-compose ps -q kafka)
if [ -z "$KAFKA_CONTAINER" ]; then
  echo "Kafka container not found. Exiting." >&2
  exit 2
fi

echo "Creating topics nexus.discovery.raw and nexus.discovery.normalized (3 partitions)..."
docker exec -i "$KAFKA_CONTAINER" kafka-topics --create --topic nexus.discovery.raw --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true
docker exec -i "$KAFKA_CONTAINER" kafka-topics --create --topic nexus.discovery.normalized --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 || true

echo "Current topics:"
docker exec -i "$KAFKA_CONTAINER" kafka-topics --list --bootstrap-server localhost:9092

echo "Done."
