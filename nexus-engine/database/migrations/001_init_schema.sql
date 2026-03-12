-- PostgreSQL schema for NEXUS discovery system
-- Multi-tenant focused, with RLS for isolation

-- Tenants (customer isolation)
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR NOT NULL UNIQUE,
    gitlab_url VARCHAR,
    github_org VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Core pipeline runs
CREATE TABLE IF NOT EXISTS runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    source VARCHAR NOT NULL, -- github|gitlab|jenkins|bitbucket
    repo VARCHAR NOT NULL,
    branch VARCHAR NOT NULL,
    status VARCHAR NOT NULL, -- success|failed|running|cancelled
    duration_ms INTEGER,
    estimated_cost DECIMAL(10, 4),
    environment VARCHAR, -- dev|staging|prod|custom
    triggered_by VARCHAR,
    commit_sha VARCHAR,
    runner_type VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(source, repo, id) -- Prevent exact duplicates
);

CREATE INDEX IF NOT EXISTS idx_runs_tenant ON runs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_runs_repo ON runs(repo);
CREATE INDEX IF NOT EXISTS idx_runs_status ON runs(status);
CREATE INDEX IF NOT EXISTS idx_runs_created ON runs(created_at DESC);

-- Individual job steps
CREATE TABLE IF NOT EXISTS steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    status VARCHAR NOT NULL, -- success|failed|skipped
    duration_ms INTEGER,
    runner_type VARCHAR,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_steps_run ON steps(run_id);
CREATE INDEX IF NOT EXISTS idx_steps_tenant ON steps(tenant_id);

-- Audit log (track all mutations)
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    action VARCHAR NOT NULL,
    actor VARCHAR,
    resource_type VARCHAR,
    resource_id VARCHAR,
    changes JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_tenant ON audit_log(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at DESC);

-- Row-Level Security (RLS) for multi-tenancy
ALTER TABLE runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE steps ENABLE ROW LEVEL SECURITY;

-- RLS policies: users can only see their tenant's data
CREATE POLICY tenant_isolation_runs ON runs
    USING (tenant_id = CURRENT_SETTING('app.tenant_id')::UUID);

CREATE POLICY tenant_isolation_steps ON steps
    USING (tenant_id = CURRENT_SETTING('app.tenant_id')::UUID);

-- Function to automatically set tenant_id from JWT or session
CREATE OR REPLACE FUNCTION set_tenant_id(tenant_uuid UUID)
RETURNS void AS $$
BEGIN
    PERFORM set_config('app.tenant_id', tenant_uuid::TEXT, FALSE);
END;
$$ LANGUAGE plpgsql;

-- Function for audit logging on runs
CREATE OR REPLACE FUNCTION audit_run_change()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (tenant_id, action, actor, resource_type, resource_id, changes)
    VALUES (
        NEW.tenant_id,
        TG_OP,
        CURRENT_USER,
        'run',
        NEW.id::TEXT,
        row_to_json(NEW)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_audit_runs
    AFTER INSERT OR UPDATE ON runs
    FOR EACH ROW EXECUTE FUNCTION audit_run_change();
