# Contributing to NexusShield Portal

Thank you for contributing to the NexusShield Portal backend! This guide outlines our development standards and workflow.

---

## 🚀 Quick Start

### Prerequisites
- Node.js 18+
- npm 8+
- Docker & Docker Compose
- PostgreSQL 15
- Redis 7

### Development Environment

```bash
# Clone the repository
git clone https://github.com/kushin77/self-hosted-runner.git
cd self-hosted-runner

# Install backend dependencies
cd backend
npm install
npm run dev:watch

# In another terminal, start the stack
cd ..
docker-compose up -d

# Verify it's working
curl http://192.168.168.42:3000/ready
```

---

## 📋 Development Workflow

### 1. Create a Feature Branch

```bash
# Update main first
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/my-feature-name

# Naming convention:
# feature/add-auth-middleware          (new feature)
# fix/dashboard-crash                  (bug fix)
# refactor/simplify-service            (code improvement)
# docs/update-api-reference            (documentation)
```

### 2. Before Writing Code

- [ ] Read the architecture overview: [docs/architecture/](docs/architecture/)
- [ ] Check existing API endpoints: [backend/README.md](backend/README.md)
- [ ] Review database schema: [backend/prisma/schema.prisma](backend/prisma/schema.prisma)
- [ ] Verify deployment target: **192.168.168.42** (NEVER localhost)

### 3. Code Standards

#### TypeScript

- **Strict Mode:** Enabled (`strict: true` in tsconfig.json)
- **No any:** Use explicit types wherever possible
- **Async/Await:** Preferred over callbacks
- **Error Handling:** Use try-catch with specific error types

```typescript
// ✅ GOOD
async function createCredential(request: CredentialRequest): Promise<Credential> {
  try {
    validateCredentialRequest(request);
    const credential = await prisma.credential.create({
      data: request,
    });
    return credential;
  } catch (error) {
    if (error instanceof PrismaClientKnownRequestError) {
      throw new ValidationError(`Credential creation failed: ${error.message}`);
    }
    throw error;
  }
}

// ❌ AVOID
function createCredential(request) {
  const credential = prisma.credential.create(request); // no error handling
  return credential;
}
```

#### Express Middleware

- Create reusable middleware in `src/middleware/`
- Always include request ID tracing
- Log security-relevant events

```typescript
// src/middleware/authMiddleware.ts
export function authMiddleware(req: Request, res: Response, next: NextFunction): void {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }
  try {
    const decoded = verifyJWT(token);
    (req as any).user = decoded;
    next();
  } catch (error) {
    res.status(403).json({ error: 'Invalid token' });
  }
}
```

### 4. Testing

```bash
# Run tests
npm test

# Run with coverage
npm test -- --coverage

# Test TypeScript compilation
npm run build

# Lint check
npm run lint -- --fix
```

#### Test Conventions

- Create `.test.ts` files next to source files
- Use descriptive test names
- Test happy path, edge cases, and error scenarios
- Mock external dependencies

```typescript
// credential.service.test.ts
describe('CredentialService', () => {
  it('should create a credential with valid input', async () => {
    const result = await credentialService.create(validInput);
    expect(result).toHaveProperty('id');
    expect(result.type).toBe('gcp');
  });

  it('should throw ValidationError with invalid email', async () => {
    await expect(
      credentialService.create({ ...validInput, email: 'invalid' })
    ).rejects.toThrow(ValidationError);
  });
});
```

### 5. Git Commits

#### Commit Message Format

```
type: concise description (50 chars max)

Longer explanation of what changed and why (if needed).
Keep to 72 chars per line for readability.

Fixes: #1234
Closes: #5678
```

#### Commit Types

```
feat:     New feature
fix:      Bug fix
refactor: Code reorganization (no behavior change)
docs:     Documentation changes
test:     Test additions/changes
chore:    Dependencies, tooling, build system
perf:     Performance improvements
```

#### Examples

```
✅ GOOD
feat: add JWT token rotation endpoint

Implements automatic token rotation with configurable TTL.
Endpoints: POST /auth/rotate, GET /auth/token-info.

Fixes: #1234

❌ AVOID
updated code
fixed bug
new feature
WIP
```

### 6. Direct-Deploy Workflow (NO PRs / NO GitHub Actions)

This repository follows a direct-development, direct-deploy model. There are no GitHub Actions or PR-based release gates. Follow these rules when making changes and pushing directly to `main`:

1. Update your local `main` and run full local tests:

```bash
git checkout main
git pull origin main
# make your changes on a short-lived branch
git checkout -b work/brief-description
# run tests and linters locally
cd backend && npm test && npm run lint
```

2. Commit with a clear conventional commit message (see "Commit Message Format").

3. Push directly to `main` only when:
  - All tests pass locally (`npm test` / `pytest` / type-checks). 
  - Linting and formatting are clean.
  - Changes are documented in `REFactor_CHANGES_*.md` when they affect architecture or workflow.

```bash
git add .
git commit -m "fix: brief description (affects: backend, telemetry)"
git checkout main
git merge --no-ff work/brief-description
git push origin main
```

4. After push, the repository's deployment automation (Cloud Build / in-repo deployment scripts) will perform the hands-off deployment. Do not rely on GitHub Actions or PR merges for releases.

5. If a change requires review, open a short-lived issue and request a reviewer; include a clear summary and testing notes. Reviewers will validate and respond; merge when agreed.

---

## 🏗️ Architecture Guidelines

### Backend Structure

```
backend/
├── src/
│   ├── index.ts           # Express app initialization
│   ├── middleware/        # Reusable middleware
│   ├── routes/            # API route handlers
│   ├── services/          # Business logic
│   ├── utils/             # Helper functions
│   └── types.ts           # TypeScript interfaces
├── prisma/
│   └── schema.prisma      # Database schema
├── package.json           # Dependencies
├── tsconfig.json          # TypeScript config
├── Dockerfile             # Production image
└── docker-compose.yml     # Local development stack
```

### Key Principles

1. **Separation of Concerns**
   - Routes handle HTTP layer
   - Services handle business logic
   - Middleware handles cross-cutting concerns
   - Utils handle reusable functions

2. **Immutability**
   - Soft deletes (mark deleted, never remove)
   - Audit trail for all state changes
   - Version control for configuration

3. **Security**
   - Never log passwords or tokens
   - Validate all inputs
   - Use prepared statements (Prisma handles this)
   - Encrypt credentials at rest
   - Implement rate limiting

4. **Error Handling**
   - Use specific error types
   - Return meaningful HTTP status codes
   - Include request ID in logs

---

## 🔐 Security Checklist

Before submitting a PR, ensure:

- [ ] No credentials or secrets in code
- [ ] All inputs validated
- [ ] SQL injection prevented (using Prisma)
- [ ] CORS properly configured
- [ ] Authentication required for protected endpoints
- [ ] Rate limiting implemented
- [ ] Sensitive data not logged
- [ ] Error messages don't leak information
- [ ] Dependencies have no critical vulnerabilities

```bash
# Check for secrets
git diff HEAD~1 | grep -E "password|token|secret|key"

# Check for vulnerabilities
npm audit

# Scan for common patterns
grep -r "eval\|exec\|Function(" src/ || echo "No dangerous patterns found"
```

---

## 📚 Documentation

### API Documentation

When adding new endpoints:

1. Update [backend/README.md](backend/README.md) with:
   - Endpoint path and HTTP method
   - Request/response examples
   - Error responses
   - Authentication requirements

2. Add code comments for complex logic:
   ```typescript
   /**
    * Rotates JWT token for extended session.
    * @param oldToken - Current valid JWT token
    * @returns New JWT token with updated expiry
    * @throws ValidationError if token invalid
    */
   export function rotateToken(oldToken: string): string {
     // ...
   }
   ```

### Code Comments

```typescript
// ✅ GOOD: Explains WHY, not WHAT
// Use Redis cache to reduce database load for frequently accessed credentials
const cached = await redis.get(credentialKey);

// ❌ AVOID: Comments that just repeat code
// Set x to credentialKey
const x = credentialKey;
```

---

## Governance Enforcement

This repository enforces mandatory governance controls required for production readiness. All contributors and maintainers must follow these enforced rules. Violations (pushing secrets, re-adding GitHub Actions, or enabling PR-release flows) will be reverted and flagged to the security/ops team.

### Required Properties
- **Immutable**: All audit exports and critical logs must be exported as JSONL and stored in COMPLIANCE buckets with Object Lock (365-day retention). See issue #2700 for Day 2 immutability tasks.
- **Ephemeral**: All credentials must be ephemeral where possible; TTLs must be enforced via GSM or Vault (see issue #2774).
- **Idempotent**: Infrastructure changes must be idempotent. Use Terraform with plan gating and drift detection (see issue #2775).
- **No-Ops (Hands-Off)**: Deployments must be fully automated with canary/smoke tests and auto-rollback. Human operator interventions are limited and documented (see issue #2776).
- **Credentials Management**: All secrets and signing keys MUST be stored and accessed via Google Secret Manager, HashiCorp Vault, or KMS. No credentials in repo (see issue #2772).
- **Direct Development & Direct Deploy**: Developers may push to `main` following the direct-deploy policy in this doc. PR-based release gates and GitHub Actions are NOT allowed.

### Enforcement Actions
- Any `.github/workflows` files found on `main` will be archived and removed automatically by automation. A recent archive PR: #2782.
- Repository admins MUST configure branch protection on `main` to require Cloud Build checks (not GitHub Actions) and block pushes that include `.github/workflows` files.
- CI/CD must use Cloud Build / Cloud Run / Cloud Deploy; do not add or re-enable GitHub Actions.
- Security scans (secret scanning, vulnerability scans) are required daily and must pass for production deploys.

### Owner & Contacts
- **Owner:** @kushin77 (Backend + DevOps)
- **Security contact:** security@nexusshield.example.com
- **Relevant issues:** #2700 (immutability), #2684 (ops blocker), #2772 (GSM/Vault/KMS), #2773 (no-actions policy), #2774 (ephemeral creds), #2775 (idempotent infra), #2776 (no-ops automation)

If you need an exception for a specific workflow, open an issue referencing the policy and get explicit approval from the owner.

---

## 🚀 Deployment Integration

### Before Final Commit

1. **Verify Target Host**
   ```bash
   # In your .env (development)
   DEPLOYMENT_HOST=192.168.168.42  # NOT localhost
   ```

2. **Test Local Build**
   ```bash
   npm run build
docker build -t test-backend .
docker run -it test-backend npm run build
   ```

3. **Update Version**
   ```bash
   # In package.json
   "version": "1.0.X"  # Increment patch for changes
   ```

---

## 🐛 Troubleshooting Development Issues

### TypeScript compilation errors

```bash
# Clear cache and rebuild
rm -rf dist/ node_modules/.cache
npm run build
```

### Database connection issues

```bash
# Check if PostgreSQL is running
docker exec nexusshield-postgres psql -U nexusshield -d nexusshield -c "SELECT 1"

# Reset database
docker-compose down -v
docker-compose up -d postgres
```

---

## 📊 Code Review Checklist

Reviewers should check:

- [ ] Code follows TypeScript strict mode standards
- [ ] Tests added for new functionality
- [ ] No secrets or credentials in code
- [ ] Error handling is comprehensive
- [ ] Database queries are optimized
- [ ] API responses are consistent
- [ ] Documentation is updated
- [ ] Commit messages are descriptive

Commencement can merge after:
- [ ] 1 approval from core team
- [ ] No failing tests
- [ ] No merge conflicts

---

## 🎯 Common Tasks

### Adding a New Endpoint

1. **Create route handler** in `src/routes/`
2. **Implement business logic** in `src/services/`
3. **Add to Express app** in `src/index.ts`
4. **Document** in `backend/README.md`
5. **Test locally** and verify
6. **Create PR** with description

---

## 📞 Support

- **Questions?** Open an issue or discussion
- **Bug found?** File a bug report with reproduction steps
- **Feature request?** Open a discussion
- **Security concern?** Email team privately

---

## Code of Conduct

- Be respectful and inclusive
- Give constructive feedback
- Credit contributions
- Ask questions when unclear
- Help onboard new team members

---

**Happy Coding! 🚀**

For more information, see:
- [Deployment Guide](docs/deployment/DEPLOYMENT_GUIDE.md)
- [Architecture Overview](docs/architecture/)
- [API Reference](backend/README.md)
- [Troubleshooting](docs/runbooks/TROUBLESHOOTING.md)
