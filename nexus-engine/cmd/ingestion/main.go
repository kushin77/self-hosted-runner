package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"

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

	// GitHub webhook endpoint (with signature verification)
	githubSecret := os.Getenv("GITHUB_WEBHOOK_SECRET")
	mux.HandleFunc("/webhook/github", GitHubWebhookHandler(gitHubNormalizer, producer, githubSecret))

	// GitLab webhook endpoint (with token verification)
	gitlabToken := os.Getenv("GITLAB_WEBHOOK_TOKEN")
	mux.HandleFunc("/webhook/gitlab", GitLabWebhookHandler(gitLabNormalizer, producer, gitlabToken))

	// Health check
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
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
