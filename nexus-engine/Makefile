.PHONY: help build up down test clean

help:
	@echo "NEXUS Engine Phase 0 Commands"
	@echo "=============================="
	@echo "make up        - Start Kafka + PostgreSQL (via Docker)"
	@echo "make down      - Stop services"
	@echo "make build     - Build ingestion service"
	@echo "make run       - Run ingestion service locally"
	@echo "make test      - Run all tests"
	@echo "make test-integration - Run integration tests"
	@echo "make db-migrate - Apply database migrations"
	@echo "make clean     - Remove build artifacts"

up:
	@echo "Starting Kafka + PostgreSQL..."
	docker-compose -f docker-compose.yml up -d

down:
	@echo "Stopping services..."
	docker-compose -f docker-compose.yml down

build:
	@echo "Building ingestion service..."
	go build -o bin/ingestion ./cmd/ingestion

run: build
	@echo "Running ingestion service..."
	./bin/ingestion

test:
	@echo "Running unit tests..."
	go test ./... -v -race -coverprofile=coverage.out
	go tool cover -html=coverage.out -o coverage.html

test-integration:
	@echo "Running integration tests..."
	@which docker-compose > /dev/null || (echo "Docker Compose required"; exit 1)
	docker-compose up -d kafka postgres
	sleep 5
	go test ./... -v -tags=integration
	docker-compose down

db-migrate:
	@echo "Applying database migrations..."
	@which psql > /dev/null || (echo "psql required"; exit 1)
	psql -h localhost -U nexus -d nexus -f database/migrations/001_init_schema.sql

clean:
	@echo "Cleaning up..."
	rm -f bin/*
	rm -f coverage.*
	go clean
