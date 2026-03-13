// Package normalizer - Converts webhook payloads from multiple Git platforms to unified discovery.PipelineRun
package normalizer

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"

	"github.com/kushin77/self-hosted-runner/pkg/discovery"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// GitHubWorkflowPayload represents GitHub Actions workflow_run webhook
type GitHubWorkflowPayload struct {
	Action     string `json:"action"`
	WorkflowRun struct {
		ID         int64  `json:"id"`
		Name       string `json:"name"`
		Status     string `json:"status"`      // completed, in_progress, queued, requested, waiting
		Conclusion string `json:"conclusion"` // success, failure, neutral, cancelled, skipped, timed_out, action_required
		HeadBranch string `json:"head_branch"`
		HeadCommit struct {
			SHA    string `json:"sha"`
			Message string `json:"message"`
		} `json:"head_commit"`
		CreatedAt  string `json:"created_at"`
		UpdatedAt  string `json:"updated_at"`
		RunNumber  int    `json:"run_number"`
		Repository struct {
			Name     string `json:"name"`
			FullName string `json:"full_name"`
			Owner    struct {
				Login string `json:"login"`
			} `json:"owner"`
		} `json:"repository"`
		TriggerActor struct {
			Login string `json:"login"`
		} `json:"trigger_actor"`
		Event string `json:"event"` // push, pull_request, schedule, etc.
	} `json:"workflow_run"`
}

// NormalizeGitHubWorkflow converts GitHub webhook to unified PipelineRun
func NormalizeGitHubWorkflow(payload []byte) (*discovery.NormalizedEvent, error) {
	var gh GitHubWorkflowPayload
	if err := json.Unmarshal(payload, &gh); err != nil {
		return nil, fmt.Errorf("failed to unmarshal GitHub payload: %w", err)
	}

	// Only process completed workflows
	if gh.WorkflowRun.Status != "completed" && gh.WorkflowRun.Status != "in_progress" {
		return nil, fmt.Errorf("skipping non-terminal status: %s", gh.WorkflowRun.Status)
	}

	// Map GitHub status → discovery.Status
	status := mapGitHubStatus(gh.WorkflowRun.Status, gh.WorkflowRun.Conclusion)

	createdAt, _ := time.Parse(time.RFC3339, gh.WorkflowRun.CreatedAt)
	completedAt, _ := time.Parse(time.RFC3339, gh.WorkflowRun.UpdatedAt)
	durationMs := completedAt.Sub(createdAt).Milliseconds()

	run := &discovery.PipelineRun{
		Id:          fmt.Sprintf("github-%d", gh.WorkflowRun.ID),
		SourceRunId: fmt.Sprintf("%d", gh.WorkflowRun.ID),
		Source:      "github",
		Repo:        gh.WorkflowRun.Repository.FullName,
		Branch:      gh.WorkflowRun.HeadBranch,
		CommitSha:   gh.WorkflowRun.HeadCommit.SHA,
		Status:      status,
		DurationMs:  durationMs,
		TriggeredBy: gh.WorkflowRun.Event,
		StartedAt:   timestamppb.New(createdAt),
		EndedAt:     timestamppb.New(completedAt),
	}

	return &discovery.NormalizedEvent{
		PipelineRun: run,
		Source:      "github",
		ReceivedAt:  timestamppb.Now(),
		Idempotent:  true,
	}, nil
}

// VerifyGitHubSignature verifies X-Hub-Signature-256 header
func VerifyGitHubSignature(payload []byte, signature string, secret string) bool {
	expected := hmac.New(sha256.New, []byte("sha256="+secret))
	expected.Write(payload)
	expectedSig := "sha256=" + hex.EncodeToString(expected.Sum(nil))
	
	return hmac.Equal([]byte(signature), []byte(expectedSig))
}

// mapGitHubStatus converts GitHub status/conclusion to unified enum
func mapGitHubStatus(status, conclusion string) discovery.Status {
	if status == "in_progress" {
		return discovery.Status_RUNNING
	}
	if status != "completed" {
		return discovery.Status_PENDING
	}

	switch conclusion {
	case "success":
		return discovery.Status_SUCCESS
	case "failure":
		return discovery.Status_FAILED
	case "skipped":
		return discovery.Status_CANCELLED
	case "cancelled":
		return discovery.Status_CANCELLED
	case "timed_out":
		return discovery.Status_FAILED
	case "action_required":
		return discovery.Status_PENDING
	default:
		return discovery.Status_STATUS_UNSPECIFIED
	}
}

// GitLabPipelinePayload represents GitLab pipeline webhook
type GitLabPipelinePayload struct {
	ObjectKind  string `json:"object_kind"`
	Pipeline    struct {
		ID    int64  `json:"id"`
		IID   int    `json:"iid"`
		SHA   string `json:"sha"`
		Ref   string `json:"ref"`
		Status string `json:"status"` // created, waiting_for_resource, preparing, pending, running, success, failed, canceled, skipped, manual, scheduled
	} `json:"pipeline"`
	Project struct {
		ID          int    `json:"id"`
		Name        string `json:"name"`
		PathWithNamespace string `json:"path_with_namespace"`
	} `json:"project"`
	User struct {
		Username string `json:"username"`
	} `json:"user"`
	CreatedAt  string `json:"created_at"`
	FinishedAt string `json:"finished_at"`
	DurationMs int64  `json:"duration"`
}

// NormalizeGitLabPipeline converts GitLab webhook to unified PipelineRun
func NormalizeGitLabPipeline(payload []byte) (*discovery.NormalizedEvent, error) {
	var gl GitLabPipelinePayload
	if err := json.Unmarshal(payload, &gl); err != nil {
		return nil, fmt.Errorf("failed to unmarshal GitLab payload: %w", err)
	}

	if gl.ObjectKind != "pipeline" {
		return nil, fmt.Errorf("skipping non-pipeline event: %s", gl.ObjectKind)
	}

	status := mapGitLabStatus(gl.Pipeline.Status)

	createdAt, _ := time.Parse(time.RFC3339, gl.CreatedAt)
	finishedAt, _ := time.Parse(time.RFC3339, gl.FinishedAt)
	if gl.DurationMs == 0 && finishedAt.IsZero() {
		finishedAt = time.Now()
	}

	run := &discovery.PipelineRun{
		Id:          fmt.Sprintf("gitlab-%d", gl.Pipeline.ID),
		SourceRunId: fmt.Sprintf("%d", gl.Pipeline.ID),
		Source:      "gitlab",
		Repo:        gl.Project.PathWithNamespace,
		Branch:      gl.Pipeline.Ref,
		CommitSha:   gl.Pipeline.SHA,
		Status:      status,
		DurationMs:  gl.DurationMs,
		TriggeredBy: "push", // GitLab doesn't provide in webhook; default to push
		StartedAt:   timestamppb.New(createdAt),
		EndedAt:     timestamppb.New(finishedAt),
	}

	return &discovery.NormalizedEvent{
		PipelineRun: run,
		Source:      "gitlab",
		ReceivedAt:  timestamppb.Now(),
		Idempotent:  true,
	}, nil
}

// VerifyGitLabSignature verifies X-Gitlab-Token header
func VerifyGitLabSignature(token string, secret string) bool {
	return hmac.Equal([]byte(token), []byte(secret))
}

// mapGitLabStatus converts GitLab status to unified enum
func mapGitLabStatus(status string) discovery.Status {
	switch status {
	case "created", "waiting_for_resource", "preparing":
		return discovery.Status_PENDING
	case "pending", "running":
		return discovery.Status_RUNNING
	case "success":
		return discovery.Status_SUCCESS
	case "failed":
		return discovery.Status_FAILED
	case "cancelled", "skipped":
		return discovery.Status_CANCELLED
	case "manual", "scheduled":
		return discovery.Status_PENDING
	default:
		return discovery.Status_STATUS_UNSPECIFIED
	}
}
