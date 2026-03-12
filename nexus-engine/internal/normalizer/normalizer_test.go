package normalizer

import (
	"encoding/json"
	"testing"
	"time"

	"go.uber.org/zap"
	"github.com/kushin77/nexus-engine/pkg/discovery"
)

func TestMapGitHubStatus(t *testing.T) {
	cases := map[string]string{
		"success": "success",
		"failure": "failed",
		"neutral": "running",
		"timed_out": "cancelled",
	}
	for in, want := range cases {
		if got := mapGitHubStatus(in); got != want {
			t.Fatalf("mapGitHubStatus(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestInferEnvironment(t *testing.T) {
	cases := map[string]string{
		"main":       "prod",
		"master":     "prod",
		"prod-1":     "prod",
		"staging-x":  "staging",
		"feature/dev": "dev",
		"custom-branch": "custom",
	}
	for in, want := range cases {
		if got := inferEnvironment(in); got != want {
			t.Fatalf("inferEnvironment(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestGitHubNormalizer_Normalize(t *testing.T) {
	logger := zap.NewNop()
	n := NewGitHubNormalizer(logger)

	// fixed times for deterministic duration
	created := "2026-03-12T15:00:00Z"
	updated := "2026-03-12T15:01:30Z" // 90 seconds later

	payload := map[string]interface{}{
		"action": "completed",
		"workflow_run": map[string]interface{}{
			"id":  12345,
			"name": "CI",
			"conclusion": "success",
			"status": "completed",
			"head_branch": "feature/dev",
			"head_sha": "abcd1234",
			"html_url": "https://github.com/org/repo/actions/runs/12345",
			"created_at": created,
			"updated_at": updated,
			"triggering_actor": map[string]interface{}{"login": "octocat"},
		},
		"repository": map[string]interface{}{"full_name": "org/repo"},
	}

	b, _ := json.Marshal(payload)
	evt, err := n.Normalize("tenant-1", b)
	if err != nil {
		t.Fatalf("Normalize returned error: %v", err)
	}
	if evt == nil {
		t.Fatalf("Normalize returned nil event")
	}
	if evt.Repo != "org/repo" {
		t.Fatalf("unexpected repo: %s", evt.Repo)
	}
	if evt.TenantId != "tenant-1" {
		t.Fatalf("unexpected tenant: %s", evt.TenantId)
	}
	if evt.Status != "success" {
		t.Fatalf("unexpected status: %s", evt.Status)
	}
	// duration should be ~90000 ms
	if evt.DurationMs < 89900 || evt.DurationMs > 90100 {
		t.Fatalf("unexpected duration: %d", evt.DurationMs)
	}
	if evt.Environment != "dev" {
		t.Fatalf("unexpected env: %s", evt.Environment)
	}
	if evt.TriggeredBy != "octocat" {
		t.Fatalf("unexpected trigger: %s", evt.TriggeredBy)
	}
	if evt.CommitSha != "abcd1234" {
		t.Fatalf("unexpected sha: %s", evt.CommitSha)
	}
	if evt.EstimatedCost <= 0 {
		t.Fatalf("expected estimated cost > 0, got %v", evt.EstimatedCost)
	}
	// timestamp should be recent-ish
	if time.Unix(0, evt.Timestamp).After(time.Now().Add(1 * time.Minute)) {
		t.Fatalf("unexpected timestamp: %v", time.Unix(0, evt.Timestamp))
	}

	// validate metadata
	if v := evt.Metadata["workflow_name"]; v != "CI" {
		t.Fatalf("unexpected metadata.workflow_name: %s", v)
	}
}
