# NexusShield Portal — Backend API

**Status:** MVP Implementation Starting | **Language:** TypeScript/Node.js | **Framework:** Express.js

## Quick Start

```bash
cd backend
npm install
npm run dev  # Development server (hot-reload)
```

## Project Structure

```
backend/
├── src/
│   ├── app.ts              # Express app initialization
│   ├── server.ts           # HTTP server entry point
│   ├── middleware/         # Express middleware
│   │   ├── auth.ts         # OAuth 2.0 + JWT validation
│   │   ├── logging.ts      # JSONL audit logging
│   │   └── errorHandler.ts # Global error handler
│   ├── routes/
│   │   ├── credentials.ts   # Credential management endpoints
│   │   ├── deployments.ts   # Deployment orchestration endpoints
│   │   └── compliance.ts    # Compliance & audit endpoints
│   ├── services/
│   │   ├── credentialService.ts
│   │   ├── deploymentService.ts
│   │   └── complianceService.ts
│   ├── models/
│   │   ├── credential.ts
│   │   ├── deployment.ts
│   │   └── auditEntry.ts
│   ├── utils/
│   │   ├── database.ts     # PostgreSQL connection pool
│   │   ├── vault.ts        # Vault AppRole integration
│   │   ├── gsm.ts          # Google Secret Manager
│   │   └── kms.ts          # AWS KMS integration
│   └── config/
│       └── env.ts          # Environment variable validation
├── tests/
├── Dockerfile              # Container image
├── package.json
├── tsconfig.json
└── README.md
```

## API Endpoints

### Credential Management
```
POST   /api/v1/credentials/rotate          # Trigger rotation
GET    /api/v1/credentials/status          # Real-time health
GET    /api/v1/credentials/{id}/audit-log  # Immutable audit trail
DELETE /api/v1/credentials/{id}/revoke     # Revoke credential
GET    /api/v1/credentials/health/summary  # 6-point compliance
```

### Deployment Orchestration
```
POST   /api/v1/deployments/execute         # Trigger Phase workflow
GET    /api/v1/deployments/status          # Progress tracking
POST   /api/v1/deployments/{id}/rollback   # Automated rollback
GET    /api/v1/deployments/next-scheduled  # Upcoming workflows
```

### Compliance & Audit
```
GET    /api/v1/compliance/dashboard        # Real-time checks
GET    /api/v1/audit/trails/{type}         # JSONL export
GET    /api/v1/compliance/report           # PDF generation
```

## Environment Variables

```bash
# Database (PostgreSQL)
DATABASE_URL=postgresql://user:pass@host:5432/portal_main?sslmode=require

# Auth (GitHub OAuth)
GITHUB_CLIENT_ID=xxx
GITHUB_CLIENT_SECRET=xxx

# Secrets (GSM/Vault/KMS)
VAULT_ADDR=https://vault.example.com
VAULT_TOKEN=s.xxxxx (ephemeral, rotated hourly)
GCP_PROJECT_ID=xxx
AWS_KMS_KEY_ID=arn:aws:kms:us-east-1:xxx:key/xxx

# Deployment
NODE_ENV=production
PORT=3000
```

## Architecture

**Authentication (Ephemeral):**
- GitHub OAuth 2.0 (1-hour ID token)
- JWT refresh tokens (7-day TTL, stored in http-only cookies)
- RBAC: Admin, Operations Engineer, Developer, Audit

**Database (PostgreSQL):**
- Cloud SQL / RDS Multi-AZ
- Connection pooling (PgBouncer / RDS Proxy)
- Encrypted backups + PITR (point-in-time recovery)
- Immutable audit log (append-only)

**Secrets Management (Multi-Cloud):**
- Primary: Google Secret Manager (auto-rotation every 30d)
- Secondary: HashiCorp Vault AppRole (1h token TTL)
- Tertiary: AWS KMS (fallback for credential encryption)
- Emergency: Encrypted local copy (requires manual unlock)

**Immutable Logging:**
- JSONL append-only logs (stored in Git + PostgreSQL + Cloud Storage)
- Cryptographic signing (HMAC-SHA256)
- GitHub commit hashes for audit trail
- CloudTrail integration (AWS)

## Testing

```bash
# Unit tests
npm run test

# Integration tests (requires database)
npm run test:integration

# Coverage report
npm run test:coverage
```

## Deployment

**Automated via GitHub Actions:**
1. Push to main
2. \`portal-backend-build.yml\` runs:
   - Linting + formatting checks
   - Unit tests (90%+ coverage required)
   - Build Docker image
   - Scan for vulnerabilities (Trivy)
   - Push to Artifact Registry
3. Staging automatically deployed
4. Production deployment via manual approval

```bash
# Manual deployment (local development)
gcloud run deploy nexusshield-portal-api-staging \
  --image us-central1-docker.pkg.dev/PROJECT/nexusshield/portal-api:latest \
  --region us-central1 \
  --platform managed \
  --set-env-vars DATABASE_URL=$DATABASE_URL,VAULT_ADDR=$VAULT_ADDR
```

## Compliance

- **Immutable Audit Trail:** Every operation logged to JSONL + git
- **Ephemeral Credentials:** No long-lived API keys (OIDC only)
- **Encryption at Rest:** KMS-managed database encryption
- **Encryption in Transit:** TLS 1.3+ for all connections
- **SOC2 Type II:** Automated controls via monitoring + alerts

## Support

For issues, questions, or feature requests:
- GitHub Issues: https://github.com/kushin77/self-hosted-runner/issues
- Slack: #nexusshield-engineering
- Email: engineering@nexusshield.cloud

---

*This is a production application. All changes require code review and pass CI/CD checks.*
