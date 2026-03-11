#!/usr/bin/env bash
set -euo pipefail

# Deploy to staging using docker-compose. Designed to be direct-deploy (no GitHub Actions).
# Pre-requisites: docker and docker-compose installed, DOCKER_REGISTRY populated if images are remote.

COMPOSE_FILE=deploy/docker-compose.secrets.yml

echo "Bringing up stack using $COMPOSE_FILE"
docker compose -f $COMPOSE_FILE pull || true
docker compose -f $COMPOSE_FILE up -d --remove-orphans

echo "Deployment started. Use 'docker compose -f $COMPOSE_FILE ps' to check services."