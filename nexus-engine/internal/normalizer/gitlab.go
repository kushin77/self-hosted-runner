package normalizer

import (
	"encoding/json"
	"fmt"
	"time"

	"go.uber.org/zap"

	"github.com/kushin77/nexus-engine/pkg/discovery"
)

// GitLabNormalizer converts GitLab CI webhook payloads to NexusDiscoveryEvent
type GitLabNormalizer struct {
	logger *zap.Logger
}

// NewGitLabNormalizer creates a new GitLab normalizer
func NewGitLabNormalizer(logger *zap.Logger) *GitLabNormalizer {
	return &GitLabNormalizer{logger: logger}
}

// Normalize converts raw GitLab webhook to canonical format
func (n *GitLabNormalizer) Normalize(tenantID string, payload []byte) (*discovery.NexusDiscoveryEvent, error) {
	var gl GitLabWebhook
	if err := json.Unmarshal(payload, &gl); err != nil {
		return nil, fmt.Errorf("failed to unmarshal GitLab payload: %w", err)
	}

	// Skip pipelines that aren't finished
	if gl.ObjectKind != "pipeline" || gl.Pipeline.Status == "running" || gl.Pipeline.Status == "pending" {
		return nil, fmt.Errorf("skipping non-finished pipeline: status=%s", gl.Pipeline.Status)
	}

	// Map GitLab status to canonical format
	status := mapGitLabStatus(gl.Pipeline.Status)

	// Calculate duration
	finishedAt, _ := time.Parse(time.RFC3339, gl.Pipeline.FinishedAt)
	startedAt, _ := time.Parse(time.RFC3339, gl.Pipeline.StartedAt)
	durationMs := int32(finishedAt.Sub(startedAt).Milliseconds())

	// Infer environment from branch
	env := inferEnvironment(gl.Pipeline.Ref)

	// Create canonical event
	event := &discovery.NexusDiscoveryEvent{
		Id:        fmt.Sprintf("gitlab-%d-%d", gl.Pipeline.ID, startedAt.UnixNano()),
		Source:    "gitlab",
		TenantId:  tenantID,
		Repo:      gl.Project.PathWithNamespace,
		Branch:    gl.Pipeline.Ref,
		Status:    status,
		DurationMs: durationMs,
		Environment: env,
		Timestamp: time.Now().UnixNano(),
		TriggeredBy: gl.User.Username,
		CommitSha: gl.Pipeline.SHA,
		RunnerType: "self-hosted", // GitLab pipelines can be self-hosted
		Metadata: map[string]string{
			"gitlab_pipeline_id": fmt.Sprintf("%d", gl.Pipeline.ID),
			"gitlab_project_id":  fmt.Sprintf("%d", gl.Project.ID),
			"web_url":            gl.Pipeline.WebURL,
		},
	}

	// Estimate cost (rough: self-hosted runners = near-zero, but credit system exists)
	minutes := float32(durationMs) / 60000.0
	event.EstimatedCost = float32(minutes) * 0.001 // Much cheaper than GitHub

	n.logger.Debug("normalized GitLab event",
		zap.String("repo", event.Repo),
		zap.String("status", event.Status),
		zap.Int32("duration_ms", durationMs),
	)

	return event, nil
}

// GitLab webhook structures
type GitLabWebhook struct {
	ObjectKind string              `json:"object_kind"`
	Pipeline   GitLabPipeline      `json:"pipeline"`
	Project    GitLabProject       `json:"project"`
	User       GitLabUser          `json:"user"`
}

type GitLabPipeline struct {
	ID         int64  `json:"id"`
	SHA        string `json:"sha"`
	Ref        string `json:"ref"`
	Status     string `json:"status"` // success|failed|canceled|running|pending
	StartedAt  string `json:"started_at"`
	FinishedAt string `json:"finished_at"`
	WebURL     string `json:"web_url"`
}

type GitLabProject struct {
	ID                 int64  `json:"id"`
	Name               string `json:"name"`
	PathWithNamespace  string `json:"path_with_namespace"`
}

type GitLabUser struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

func mapGitLabStatus(status string) string {
	switch status {
	case "success":
		return "success"
	case "failed":
		return "failed"
	case "canceled":
		return "cancelled"
	default:
		return "running"
	}
}
