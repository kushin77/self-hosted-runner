package normalizer

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"go.uber.org/zap"

	"github.com/kushin77/nexus-engine/pkg/discovery"
)

// GitHubNormalizer converts GitHub Actions webhook payloads to NexusDiscoveryEvent
type GitHubNormalizer struct {
	logger *zap.Logger
}

// NewGitHubNormalizer creates a new GitHub normalizer
func NewGitHubNormalizer(logger *zap.Logger) *GitHubNormalizer {
	return &GitHubNormalizer{logger: logger}
}

// Normalize converts raw GitHub webhook to canonical format
func (n *GitHubNormalizer) Normalize(tenantID string, payload []byte) (*discovery.NexusDiscoveryEvent, error) {
	var gh GitHubWebhook
	if err := json.Unmarshal(payload, &gh); err != nil {
		return nil, fmt.Errorf("failed to unmarshal GitHub payload: %w", err)
	}

	// Skip non-completed runs
	if gh.Action != "completed" {
		return nil, fmt.Errorf("skipping non-completed run: action=%s", gh.Action)
	}

	// Map GitHub conclusion to canonical status
	status := mapGitHubStatus(gh.WorkflowRun.Conclusion)

	// Calculate duration
	startTime, _ := time.Parse(time.RFC3339, gh.WorkflowRun.CreatedAt)
	endTime, _ := time.Parse(time.RFC3339, gh.WorkflowRun.UpdatedAt)
	durationMs := int32(endTime.Sub(startTime).Milliseconds())

	// Infer environment from branch
	env := inferEnvironment(gh.WorkflowRun.HeadBranch)

	// Create canonical event
	event := &discovery.NexusDiscoveryEvent{
		Id:        fmt.Sprintf("github-%d-%d", gh.WorkflowRun.ID, startTime.UnixNano()),
		Source:    "github",
		TenantId:  tenantID,
		Repo:      gh.Repository.FullName,
		Branch:    gh.WorkflowRun.HeadBranch,
		Status:    status,
		DurationMs: durationMs,
		Environment: env,
		Timestamp: time.Now().UnixNano(),
		TriggeredBy: gh.WorkflowRun.Triggerer.Login,
		CommitSha: gh.WorkflowRun.HeadSha,
		RunnerType: "cloud", // GitHub Actions are cloud
		Metadata: map[string]string{
			"github_run_id":     fmt.Sprintf("%d", gh.WorkflowRun.ID),
			"workflow_name":     gh.WorkflowRun.Name,
			"html_url":          gh.WorkflowRun.HTMLURL,
		},
	}

	// Estimate cost (GitHub pricing roughly)
	// Ubuntu latest: $0.008/min, Windows: $0.016/min, macOS: $0.08/min
	minutes := float32(durationMs) / 60000.0
	event.EstimatedCost = float32(minutes) * 0.008

	n.logger.Debug("normalized GitHub event",
		zap.String("repo", event.Repo),
		zap.String("status", event.Status),
		zap.Int32("duration_ms", durationMs),
	)

	return event, nil
}

// GitHub webhook structures (from github.com/github webhook docs)
type GitHubWebhook struct {
	Action       string               `json:"action"`
	WorkflowRun  GitHubWorkflowRun    `json:"workflow_run"`
	Repository   GitHubRepository     `json:"repository"`
}

type GitHubWorkflowRun struct {
	ID          int64                 `json:"id"`
	Name        string                `json:"name"`
	Conclusion  string                `json:"conclusion"` // success|failure|neutral|cancelled|timed_out|action_required
	Status      string                `json:"status"`     // completed|in_progress
	HeadBranch  string                `json:"head_branch"`
	HeadSha     string                `json:"head_sha"`
	HTMLURL     string                `json:"html_url"`
	CreatedAt   string                `json:"created_at"`
	UpdatedAt   string                `json:"updated_at"`
	Triggerer   GitHubUser            `json:"triggering_actor"`
}

type GitHubRepository struct {
	FullName string `json:"full_name"`
}

type GitHubUser struct {
	Login string `json:"login"`
}

func mapGitHubStatus(conclusion string) string {
	switch conclusion {
	case "success":
		return "success"
	case "failure":
		return "failed"
	case "neutral":
		return "running"
	default:
		return "cancelled"
	}
}

func inferEnvironment(branch string) string {
	branch = strings.ToLower(branch)
	if strings.HasPrefix(branch, "prod") || branch == "main" || branch == "master" {
		return "prod"
	}
	if strings.Contains(branch, "staging") || strings.Contains(branch, "stage") {
		return "staging"
	}
	if strings.Contains(branch, "dev") {
		return "dev"
	}
	return "custom"
}
