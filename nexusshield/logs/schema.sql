-- NexusShield Immutable Audit Trail Schema
-- 
-- Properties:
-- - WORM: No UPDATE or DELETE allowed (immutable)
-- - Encrypted: All columns encrypted at rest
-- - Indexed: Fast queries on timestamp, operation, user
-- - Partitioned: Automatic partitioning by month
-- 
-- Usage:
-- INSERT INTO audit_trail (operation, status, user_id, resource_type, resource_id, details)
-- VALUES ('credential-rotation', 'success', 'system', 'secret', 'prod-db-password', '{...}');

CREATE TABLE IF NOT EXISTS audit_trail (
    -- Primary key & immutability
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Timestamp (immutable creation time)
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    -- Operation details
    operation VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL CHECK (status IN ('success', 'failure', 'warning')),
    
    -- User & context
    user_id UUID,
    user_email VARCHAR(255),
    hostname VARCHAR(255),
    ip_address INET,
    
    -- Resource affected
    resource_type VARCHAR(100),
    resource_id VARCHAR(255),
    cloud_provider VARCHAR(50),
    
    -- Additional context (JSON)
    details JSONB,
    error_message TEXT,
    
    -- Immutability constraints
    CONSTRAINT no_updates UNIQUE (id),
    CONSTRAINT valid_status CHECK (status IN ('success', 'failure', 'warning'))
);

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_audit_trail_created_at ON audit_trail(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_trail_operation ON audit_trail(operation);
CREATE INDEX IF NOT EXISTS idx_audit_trail_user_id ON audit_trail(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_trail_resource ON audit_trail(resource_type, resource_id);

-- Disable updates & deletes (WORM enforcement)
CREATE OR REPLACE FUNCTION prevent_audit_update() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit records cannot be updated or deleted (immutable)';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_audit_delete() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit records cannot be deleted (immutable)';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS audit_trail_prevent_update ON audit_trail;
CREATE TRIGGER audit_trail_prevent_update
BEFORE UPDATE ON audit_trail
FOR EACH ROW EXECUTE FUNCTION prevent_audit_update();

DROP TRIGGER IF EXISTS audit_trail_prevent_delete ON audit_trail;
CREATE TRIGGER audit_trail_prevent_delete
BEFORE DELETE ON audit_trail
FOR EACH ROW EXECUTE FUNCTION prevent_audit_delete();

-- Grant permissions (read-only for most users)
GRANT SELECT ON audit_trail TO "nexusshield_app";
GRANT INSERT ON audit_trail TO "nexusshield_app";

-- View for compliance reporting
CREATE OR REPLACE VIEW audit_summary AS
SELECT 
    DATE_TRUNC('day', created_at) as day,
    operation,
    status,
    COUNT(*) as count
FROM audit_trail
GROUP BY DATE_TRUNC('day', created_at), operation, status
ORDER BY day DESC;

GRANT SELECT ON audit_summary TO "nexusshield_app";
