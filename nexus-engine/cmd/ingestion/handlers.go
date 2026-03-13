package main

import (
    "context"
    "fmt"
    "io"
    "net/http"
    "time"

    "github.com/kushin77/nexus-engine/pkg/discovery"
)

// ProducerInterface is a minimal interface used by handlers to publish events.
type ProducerInterface interface {
    PublishDiscoveryEvent(ctx context.Context, event *discovery.NexusDiscoveryEvent) error
}

// NormalizerInterface is the minimal interface for normalizers.
type NormalizerInterface interface {
    Normalize(tenantID string, payload []byte) (*discovery.NexusDiscoveryEvent, error)
}

// GitHubWebhookHandler returns an http.HandlerFunc that verifies signature and optional timestamp, normalizes and publishes event.
func GitHubWebhookHandler(normalizer NormalizerInterface, producer ProducerInterface, secret string) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        body, err := io.ReadAll(r.Body)
        if err != nil {
            http.Error(w, "invalid payload", http.StatusBadRequest)
            return
        }

        sigHeader := r.Header.Get("X-Hub-Signature-256")
        // optional time header to mitigate replay attacks
        sentAt := r.Header.Get("X-Hub-Sent-At")
        if sentAt != "" {
            if t, err := time.Parse(time.RFC3339, sentAt); err == nil {
                if time.Since(t) > 5*time.Minute || time.Until(t) > 1*time.Minute {
                    http.Error(w, "stale signature", http.StatusUnauthorized)
                    return
                }
            }
        }

        if !VerifyGitHubSignature(body, sigHeader, secret) {
            http.Error(w, "invalid signature", http.StatusUnauthorized)
            return
        }

        event, err := normalizer.Normalize("github-org", body)
        if err != nil {
            http.Error(w, "invalid payload", http.StatusBadRequest)
            return
        }

        if err := producer.PublishDiscoveryEvent(r.Context(), event); err != nil {
            http.Error(w, "internal error", http.StatusInternalServerError)
            return
        }

        w.WriteHeader(http.StatusOK)
        fmt.Fprintf(w, `{"status":"ok","id":"%s"}`, event.Id)
    }
}

// GitLabWebhookHandler verifies token header and processes GitLab pipeline events.
func GitLabWebhookHandler(normalizer NormalizerInterface, producer ProducerInterface, token string) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        body, err := io.ReadAll(r.Body)
        if err != nil {
            http.Error(w, "invalid payload", http.StatusBadRequest)
            return
        }

        header := r.Header.Get("X-Gitlab-Token")
        if header == "" || header != token {
            http.Error(w, "invalid token", http.StatusUnauthorized)
            return
        }

        event, err := normalizer.Normalize("gitlab-org", body)
        if err != nil {
            http.Error(w, "invalid payload", http.StatusBadRequest)
            return
        }

        if err := producer.PublishDiscoveryEvent(r.Context(), event); err != nil {
            http.Error(w, "internal error", http.StatusInternalServerError)
            return
        }

        w.WriteHeader(http.StatusOK)
        fmt.Fprintf(w, `{"status":"ok","id":"%s"}`, event.Id)
    }
}
