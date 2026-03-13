package normalizer

import (
	"testing"

	"github.com/kushin77/self-hosted-runner/pkg/discovery"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestNormalizeGitHubWorkflow_Success verifies GitHub workflow normalization
func TestNormalizeGitHubWorkflow_Success(t *testing.T) {
	payload := []byte(`{
		"action": "completed",
		"workflow_run": {
			"id": 12345,
			"name": "CI",
			"status": "completed",
			"conclusion": "success",
			"head_branch": "main",
			"head_commit": {
				"sha": "abc1234567890def",
				"message": "feat: add normalizer"
			},
			"created_at": "2026-03-13T10:00:00Z",
			"updated_at": "2026-03-13T10:05:30Z",
			"run_number": 42,
			"repository": {
				"name": "self-hosted-runner",
				"full_name": "kushin77/self-hosted-runner",
				"owner": {"login": "kushin77"}
			},
			"trigger_actor": {"login": "kushin77"},
			"event": "push"
		}
	}`)

	event, err := NormalizeGitHubWorkflow(payload)
	require.NoError(t, err)
	require.NotNil(t, event)

	assert.Equal(t, "github", event.Source)
	assert.Equal(t, discovery.Status_SUCCESS, event.PipelineRun.Status)
	assert.Equal(t, "github-12345", event.PipelineRun.Id)
	assert.Equal(t, "12345", event.PipelineRun.SourceRunId)
	assert.Equal(t, "kushin77/self-hosted-runner", event.PipelineRun.Repo)
	assert.Equal(t, "main", event.PipelineRun.Branch)
	assert.Equal(t, "abc1234567890def", event.PipelineRun.CommitSha)
	assert.Equal(t, int64(330000), event.PipelineRun.DurationMs) // 5.5 minutes
	assert.Equal(t, "push", event.PipelineRun.TriggeredBy)
	assert.True(t, event.Idempotent)
}

// TestNormalizeGitHubWorkflow_FailureStatus verifies failure mapping
func TestNormalizeGitHubWorkflow_FailureStatus(t *testing.T) {
	payload := []byte(`{
		"action": "completed",
		"workflow_run": {
			"id": 12346,
			"status": "completed",
			"conclusion": "failure",
			"head_branch": "feature",
			"head_commit": {"sha": "def9876543210abc"},
			"created_at": "2026-03-13T10:00:00Z",
			"updated_at": "2026-03-13T10:02:00Z",
			"repository": {"full_name": "kushin77/test", "owner": {"login": "kushin77"}}
		}
	}`)

	event, err := NormalizeGitHubWorkflow(payload)
	require.NoError(t, err)
	assert.Equal(t, discovery.Status_FAILED, event.PipelineRun.Status)
}

// TestNormalizeGitHubWorkflow_InProgress verifies running status
func TestNormalizeGitHubWorkflow_InProgress(t *testing.T) {
	payload := []byte(`{
		"action": "in_progress",
		"workflow_run": {
			"id": 12347,
			"status": "in_progress",
			"conclusion": null,
			"head_branch": "main",
			"head_commit": {"sha": "xyz123"},
			"created_at": "2026-03-13T11:00:00Z",
			"updated_at": "2026-03-13T11:00:30Z",
			"repository": {"full_name": "kushin77/test", "owner": {"login": "kushin77"}}
		}
	}`)

	event, err := NormalizeGitHubWorkflow(payload)
	require.NoError(t, err)
	assert.Equal(t, discovery.Status_RUNNING, event.PipelineRun.Status)
}

// TestVerifyGitHubSignature_Valid verifies signature validation
func TestVerifyGitHubSignature_Valid(t *testing.T) {
	payload := []byte("test payload")
	secret := "test-secret"

	// Create valid signature
	expectedSig := "sha256=ce4e8e7f3b844f87e40fd47de9e36b0947c6f3a15c2851b57dde64ce20f1f0fd"
	
	// Actually compute it
	import "crypto/hmac"
	import "crypto/sha256"
	import "encoding/hex"
	h := hmac.New(sha256.New, []byte(secret))
	h.Write(payload)
	expectedSig = "sha256=" + hex.EncodeToString(h.Sum(nil))

	isValid := VerifyGitHubSignature(payload, expectedSig, secret)
	assert.True(t, isValid)
}

// TestVerifyGitHubSignature_Invalid verifies signature rejection
func TestVerifyGitHubSignature_Invalid(t *testing.T) {
	payload := []byte("test payload")
	secret := "test-secret"
	wrongSig := "sha256=wrongsignature0000000000000000000000000000000000000000000"

	isValid := VerifyGitHubSignature(payload, wrongSig, secret)
	assert.False(t, isValid)
}

// TestNormalizeGitLabPipeline_Success verifies GitLab normalization
func TestNormalizeGitLabPipeline_Success(t *testing.T) {
	payload := []byte(`{
		"object_kind": "pipeline",
		"pipeline": {
			"id": 54321,
			"iid": 5,
			"sha": "def1234567890abc",
			"ref": "develop",
			"status": "success"
		},
		"project": {
			"id": 1001,
			"name": "myproject",
			"path_with_namespace": "mygroup/myproject"
		},
		"user": {"username": "alice"},
		"created_at": "2026-03-13T12:00:00Z",
		"finished_at": "2026-03-13T12:03:00Z",
		"duration": 180000
	}`)

	event, err := NormalizeGitLabPipeline(payload)
	require.NoError(t, err)

	assert.Equal(t, "gitlab", event.Source)
	assert.Equal(t, discovery.Status_SUCCESS, event.PipelineRun.Status)
	assert.Equal(t, "gitlab-54321", event.PipelineRun.Id)
	assert.Equal(t, "54321", event.PipelineRun.SourceRunId)
	assert.Equal(t, "mygroup/myproject", event.PipelineRun.Repo)
	assert.Equal(t, "develop", event.PipelineRun.Branch)
	assert.Equal(t, "def1234567890abc", event.PipelineRun.CommitSha)
	assert.Equal(t, int64(180000), event.PipelineRun.DurationMs)
}

// TestNormalizeGitLabPipeline_Failed verifies failure status
func TestNormalizeGitLabPipeline_Failed(t *testing.T) {
	payload := []byte(`{
		"object_kind": "pipeline",
		"pipeline": {
			"id": 54322,
			"sha": "xyz999",
			"ref": "feature",
			"status": "failed"
		},
		"project": {
			"id": 1001,
			"path_with_namespace": "mygroup/myproject"
		},
		"user": {"username": "bob"},
		"created_at": "2026-03-13T13:00:00Z",
		"finished_at": "2026-03-13T13:05:00Z",
		"duration": 300000
	}`)

	event, err := NormalizeGitLabPipeline(payload)
	require.NoError(t, err)
	assert.Equal(t, discovery.Status_FAILED, event.PipelineRun.Status)
}

// TestNormalizeGitLabPipeline_Running verifies running status
func TestNormalizeGitLabPipeline_Running(t *testing.T) {
	payload := []byte(`{
		"object_kind": "pipeline",
		"pipeline": {
			"id": 54323,
			"sha": "run123",
			"ref": "main",
			"status": "running"
		},
		"project": {"id": 1001, "path_with_namespace": "mygroup/p"},
		"user": {"username": "charlie"},
		"created_at": "2026-03-13T14:00:00Z",
		"finished_at": "2026-03-13T14:02:00Z",
		"duration": 120000
	}`)

	event, err := NormalizeGitLabPipeline(payload)
	require.NoError(t, err)
	assert.Equal(t, discovery.Status_RUNNING, event.PipelineRun.Status)
}

// BenchmarkNormalizeGitHub benchmarks GitHub normalization
func BenchmarkNormalizeGitHub(b *testing.B) {
	payload := []byte(`{
		"action": "completed",
		"workflow_run": {
			"id": 12345,
			"name": "CI",
			"status": "completed",
			"conclusion": "success",
			"head_branch": "main",
			"head_commit": {"sha": "abc1234567890def"},
			"created_at": "2026-03-13T10:00:00Z",
			"updated_at": "2026-03-13T10:05:30Z",
			"run_number": 42,
			"repository": {"full_name": "kushin77/self-hosted-runner", "owner": {"login": "kushin77"}},
			"trigger_actor": {"login": "kushin77"},
			"event": "push"
		}
	}`)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		NormalizeGitHubWorkflow(payload)
	}
}

// BenchmarkNormalizeGitLab benchmarks GitLab normalization
func BenchmarkNormalizeGitLab(b *testing.B) {
	payload := []byte(`{
		"object_kind": "pipeline",
		"pipeline": {
			"id": 54321,
			"sha": "def1234567890abc",
			"ref": "develop",
			"status": "success"
		},
		"project": {"id": 1001, "path_with_namespace": "mygroup/myproject"},
		"user": {"username": "alice"},
		"created_at": "2026-03-13T12:00:00Z",
		"finished_at": "2026-03-13T12:03:00Z",
		"duration": 180000
	}`)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		NormalizeGitLabPipeline(payload)
	}
}
