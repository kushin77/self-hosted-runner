package discovery

// Minimal hand-written structs to satisfy internal package imports
// These mirror the expected fields from proto/discovery.proto

type NexusDiscoveryEvent struct {
    Id            string            `json:"id"`
    Source        string            `json:"source"`
    TenantId      string            `json:"tenant_id"`
    Repo          string            `json:"repo"`
    Branch        string            `json:"branch"`
    Status        string            `json:"status"`
    DurationMs    int32             `json:"duration_ms"`
    Environment   string            `json:"environment"`
    EstimatedCost float32           `json:"estimated_cost"`
    Steps         []Step            `json:"steps"`
    Tags          []string          `json:"tags"`
    EnvVars       []string          `json:"env_vars_required"`
    Secrets       []string          `json:"secrets_referenced"`
    Timestamp     int64             `json:"timestamp"`
    Metadata      map[string]string `json:"metadata"`
    TriggeredBy   string            `json:"triggered_by"`
    CommitSha     string            `json:"commit_sha"`
    PullRequestId string            `json:"pull_request_id"`
    RunnerType    string            `json:"runner_type"`
}

type Step struct {
    Name       string   `json:"name"`
    Status     string   `json:"status"`
    DurationMs int32    `json:"duration_ms"`
    RunnerType string   `json:"runner_type"`
    Logs       []string `json:"logs"`
}

type RawWebhookPayload struct {
    Source    string `json:"source"`
    TenantId  string `json:"tenant_id"`
    Payload   []byte `json:"payload"`
    Signature string `json:"signature"`
    Timestamp int64  `json:"timestamp"`
}

type NormalizerResponse struct {
    Event    *NexusDiscoveryEvent `json:"event"`
    Valid    bool                 `json:"valid"`
    Errors   []string             `json:"errors"`
    Warnings []string             `json:"warnings"`
}
