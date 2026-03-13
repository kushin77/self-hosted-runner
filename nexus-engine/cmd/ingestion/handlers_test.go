package main

import (
    "bytes"
    "context"
    "encoding/hex"
    "crypto/hmac"
    "crypto/sha256"
    "net/http"
    "net/http/httptest"
    "testing"
    "time"

    "go.uber.org/zap"
    "github.com/kushin77/nexus-engine/pkg/discovery"
    "github.com/kushin77/nexus-engine/internal/normalizer"
)

type mockProducer struct{
    last *discovery.NexusDiscoveryEvent
}

func (m *mockProducer) PublishDiscoveryEvent(ctx context.Context, event *discovery.NexusDiscoveryEvent) error {
    m.last = event
    return nil
}

func TestGitHubHandler_MissingSignature(t *testing.T) {
    logger := zap.NewNop()
    n := normalizer.NewGitHubNormalizer(logger)
    mp := &mockProducer{}

    handler := GitHubWebhookHandler(n, mp, "secret")
    payload := []byte(`{"action":"completed","workflow_run": {"id":1}}`)

    req := httptest.NewRequest("POST", "/webhook/github", bytes.NewReader(payload))
    rr := httptest.NewRecorder()

    handler(rr, req)
    if rr.Code != http.StatusUnauthorized {
        t.Fatalf("expected 401 for missing signature, got %d", rr.Code)
    }
}

func TestGitHubHandler_InvalidSignature(t *testing.T) {
    logger := zap.NewNop()
    n := normalizer.NewGitHubNormalizer(logger)
    mp := &mockProducer{}

    handler := GitHubWebhookHandler(n, mp, "secret")
    payload := []byte(`{"action":"completed","workflow_run": {"id":1}}`)

    req := httptest.NewRequest("POST", "/webhook/github", bytes.NewReader(payload))
    req.Header.Set("X-Hub-Signature-256", "sha256=deadbeef")
    rr := httptest.NewRecorder()

    handler(rr, req)
    if rr.Code != http.StatusUnauthorized {
        t.Fatalf("expected 401 for invalid signature, got %d", rr.Code)
    }
}

func TestGitHubHandler_ValidSignatureAndTimestamp(t *testing.T) {
    logger := zap.NewNop()
    n := normalizer.NewGitHubNormalizer(logger)
    mp := &mockProducer{}

    secret := "mysecret"
    handler := GitHubWebhookHandler(n, mp, secret)
    payload := []byte(`{"action":"completed","workflow_run": {"id":12345,"name":"CI","conclusion":"success","status":"completed","head_branch":"main","head_sha":"a1b2c3","html_url":"https://" ,"created_at":"2026-03-12T10:00:00Z","updated_at":"2026-03-12T10:01:00Z","triggering_actor":{"login":"user"}},"repository":{"full_name":"org/repo"}}`)

    mac := hmac.New(sha256.New, []byte(secret))
    mac.Write(payload)
    sig := hex.EncodeToString(mac.Sum(nil))
    header := "sha256=" + sig

    req := httptest.NewRequest("POST", "/webhook/github", bytes.NewReader(payload))
    req.Header.Set("X-Hub-Signature-256", header)
    req.Header.Set("X-Hub-Sent-At", time.Now().UTC().Format(time.RFC3339))
    rr := httptest.NewRecorder()

    handler(rr, req)
    if rr.Code != http.StatusOK {
        t.Fatalf("expected 200 for valid signature, got %d, body=%s", rr.Code, rr.Body.String())
    }
    if mp.last == nil {
        t.Fatalf("expected event to be published")
    }
}

func TestGitHubHandler_ReplayOldTimestamp(t *testing.T) {
    logger := zap.NewNop()
    n := normalizer.NewGitHubNormalizer(logger)
    mp := &mockProducer{}

    secret := "mysecret"
    handler := GitHubWebhookHandler(n, mp, secret)
    payload := []byte(`{"action":"completed","workflow_run": {"id":12345}}`)

    mac := hmac.New(sha256.New, []byte(secret))
    mac.Write(payload)
    sig := hex.EncodeToString(mac.Sum(nil))
    header := "sha256=" + sig

    // timestamp 10 minutes ago
    old := time.Now().Add(-10 * time.Minute).UTC().Format(time.RFC3339)

    req := httptest.NewRequest("POST", "/webhook/github", bytes.NewReader(payload))
    req.Header.Set("X-Hub-Signature-256", header)
    req.Header.Set("X-Hub-Sent-At", old)
    rr := httptest.NewRecorder()

    handler(rr, req)
    if rr.Code != http.StatusUnauthorized {
        t.Fatalf("expected 401 for old timestamp replay, got %d", rr.Code)
    }
}
