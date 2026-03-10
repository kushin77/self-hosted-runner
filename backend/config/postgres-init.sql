-- PostgreSQL initialization script for NexusShield Portal
-- Runs automatically on first container startup

CREATE SCHEMA IF NOT EXISTS public;

-- Table for Users
CREATE TABLE IF NOT EXISTS "User" (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  "name" TEXT,
  "role" TEXT DEFAULT 'viewer',
  oauth_id TEXT UNIQUE,
  oauth_provider TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP
);

-- Table: Credentials (secrets management)
CREATE TABLE IF NOT EXISTS "Credential" (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  "name" TEXT NOT NULL,
  "value" TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  deleted_at TIMESTAMP,
  UNIQUE(type, "name")
);

-- Table: Rotation History (immutable audit trail)
CREATE TABLE IF NOT EXISTS "RotationHistory" (
  id TEXT PRIMARY KEY,
  "credentialId" TEXT NOT NULL REFERENCES "Credential"(id) ON DELETE CASCADE,
  old_value_hash TEXT NOT NULL,
  new_value_hash TEXT NOT NULL,
  rotation_reason TEXT,
  rotated_by TEXT,
  rotated_at TIMESTAMP DEFAULT NOW()
);

-- Table: Access Logs (security audit)
CREATE TABLE IF NOT EXISTS "AccessLog" (
  id TEXT PRIMARY KEY,
  "credentialId" TEXT NOT NULL REFERENCES "Credential"(id) ON DELETE CASCADE,
  action TEXT,
  accessed_by TEXT,
  accessed_at TIMESTAMP DEFAULT NOW(),
  ip_address TEXT,
  user_agent TEXT,
  status TEXT
);

-- Table: Audit Logs (immutable append-only blockchain-like)
CREATE TABLE IF NOT EXISTS "AuditLog" (
  id TEXT PRIMARY KEY,
  event TEXT,
  resource_type TEXT,
  resource_id TEXT,
  actor_id TEXT,
  action TEXT,
  details TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  "hash" TEXT UNIQUE,
  previous_hash TEXT
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_credential_type ON "Credential"(type);
CREATE INDEX IF NOT EXISTS idx_credential_created_at ON "Credential"(created_at);
CREATE INDEX IF NOT EXISTS idx_rotation_history_credential ON "RotationHistory"("credentialId");
CREATE INDEX IF NOT EXISTS idx_rotation_history_rotated_at ON "RotationHistory"(rotated_at);
CREATE INDEX IF NOT EXISTS idx_access_log_credential ON "AccessLog"("credentialId");
CREATE INDEX IF NOT EXISTS idx_access_log_accessed_at ON "AccessLog"(accessed_at);
CREATE INDEX IF NOT EXISTS idx_access_log_accessed_by ON "AccessLog"(accessed_by);
CREATE INDEX IF NOT EXISTS idx_audit_log_resource_type ON "AuditLog"(resource_type);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON "AuditLog"(created_at);
CREATE INDEX IF NOT EXISTS idx_user_email ON "User"(email);

-- Insert demo admin user
INSERT INTO "User" (id, email, "name", "role", created_at, updated_at)
VALUES (
  'admin-' || substr(md5(random()::text), 1, 12),
  'admin@nexusshield.local',
  'Portal Admin',
  'admin',
  NOW(),
  NOW()
)
ON CONFLICT (email) DO NOTHING;

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO nexusshield;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO nexusshield;
