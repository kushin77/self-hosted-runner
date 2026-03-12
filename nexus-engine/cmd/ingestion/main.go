package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"io"

	"github.com/joho/godotenv"
	"go.uber.org/zap"

	"github.com/kushin77/nexus-engine/internal/kafka"
	"github.com/kushin77/nexus-engine/internal/normalizer"
)

func main() {
	// Load environment
	godotenv.Load()

	// Logger
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	kafkaBrokers := os.Getenv("KAFKA_BROKERS")
	if kafkaBrokers == "" {
		kafkaBrokers = "localhost:9092"
	}

	// Create Kafka producer
	producer, err := kafka.NewProducer(kafkaBrokers, logger)
	if err != nil {
		logger.Fatal("failed to create kafka producer", zap.Error(err))
	}
	defer producer.Close()

	// Create normalizers
	gitHubNormalizer := normalizer.NewGitHubNormalizer(logger)
	gitLabNormalizer := normalizer.NewGitLabNormalizer(logger)

	// HTTP server for webhooks
	mux := http.NewServeMux()

	// GitHub webhook endpoint
	mux.HandleFunc("POST /webhook/github", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)

		event, err := gitHubNormalizer.Normalize("github-org", body)
		if err != nil {
			logger.Warn("failed to normalize github event", zap.Error(err))
			http.Error(w, "invalid payload", http.StatusBadRequest)
			return
		}

		if err := producer.PublishDiscoveryEvent(r.Context(), event); err != nil {
			logger.Error("failed to publish event", zap.Error(err))
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","id":"%s"}`, event.Id)
	})

	// GitLab webhook endpoint
	mux.HandleFunc("POST /webhook/gitlab", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)

		event, err := gitLabNormalizer.Normalize("gitlab-org", body)
		if err != nil {
			logger.Warn("failed to normalize gitlab event", zap.Error(err))
			http.Error(w, "invalid payload", http.StatusBadRequest)
			return
		}

		if err := producer.PublishDiscoveryEvent(r.Context(), event); err != nil {
			logger.Error("failed to publish event", zap.Error(err))
			http.Error(w, "internal error", http.StatusInternalServerError)
			return
		}

		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"status":"ok","id":"%s"}`, event.Id)
	})

	// Health check
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, `{"status":"healthy"}`)
	})

	// Start server
	server := &http.Server{
		Addr:    ":8080",
		Handler: mux,
	}

	logger.Info("starting ingestion service", zap.String("addr", server.Addr))

	// Graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("server error", zap.Error(err))
		}
	}()

	<-sigChan
	logger.Info("shutting down")
	server.Shutdown(context.Background())
}
