# Test Mock Configurations

## Directory Structure

```
backend/tests/
├── config/
│   └── test.env           # Test environment variables
├── fixtures/
│   └── index.ts          # Real test data for use with actual configs
├── mocks/
│   └── index.ts          # Mock factory functions
├── setup.ts              # Jest setup and configuration
├── unit/                 # Unit tests
│   ├── services/
│   └── validation.test.ts
└── integration/          # Integration tests
```

## Configuration Files

### `backend/tests/config/test.env`
Test-specific environment configuration with:
- Database URL for test DB
- Test JWT secrets
- Test GCP project IDs
- Disabled external services (Vault)

### `backend/tests/fixtures/index.ts`
Real test data including:
- `testCredentials` - GSM, Vault, KMS credentials
- `testUsers` - Admin, Operator, Viewer roles
- `testPolicies` - Password and API key policies
- `testAuditEvents` - Various audit event types
- `testApiEndpoints` - API endpoint definitions
- `testComplianceViolations` - Compliance test cases

## Mock Files

### `backend/tests/mocks/index.ts`
Factory functions for creating mock objects:

| Mock | Methods |
|------|---------|
| Prisma | auditLog, credential, credentialPolicy, scheduledRotation, rotationHistory, systemMetrics, complianceEvent |
| GCP Secret Manager | accessSecret, getSecret, addSecretVersion, createSecret |
| Vault | read, write, destroy |
| KMS | decrypt, encrypt |
| JWT | sign, verify |
| Redis | get, set, del, exists, expire, ttl |
| Crypto | createHash, randomBytes, createHmac, randomUUID |
| Logger | info, warn, error, debug, log |

### `backend/tests/setup.ts`
Jest setup file that:
- Provides TextEncoder/TextDecoder polyfills
- Loads test environment configuration
- Mocks Prisma wrapper globally
- Sets up custom Jest matchers

## Usage

### Running Tests
```bash
cd backend

# Run all tests
npm test

# Watch mode
npm run test:watch

# With coverage
npm run test:cov

# Specific test file
npm test -- auth.test.ts
```

### Using Real Configurations
Tests can use real configurations by:
1. Setting environment variables in `tests/config/test.env`
2. Using fixtures from `tests/fixtures/index.ts`
3. Connecting to actual test database

### Using Mocks
For isolated unit tests, use mocks:
```typescript
import { createMockPrisma } from './mocks';

const mockPrisma = createMockPrisma();
```
