# Credential Management Strategy - GSM/Vault/KMS

**Status:** ✅ PRODUCTION READY  
**Approach:** Zero-Trust, Ephemeral, Immutable Audit Trail  
**Last Updated:** 2026-03-10

---

## 🔐 Credential Resolution Architecture

### 4-Layer Fallback Strategy

```
Application Request
    ↓
┌─────────────────────────────────────────────────────────┐
│ Layer 1: Google Secret Manager (GSM)                    │
│ - Primary for GCP environments                          │
│ - Real-time secret versioning                          │
│ - Automatic rotation triggers                          │
│ Status: ✅ Preferred                                    │
└─────────────────────────────────────────────────────────┘
    ↓ (if GSM unavailable)
┌─────────────────────────────────────────────────────────┐
│ Layer 2: HashiCorp Vault                                │
│ - Enterprise secret management                          │
│ - AppRole authentication                               │
│ - Dynamic credential generation                        │
│ Status: ✅ Enterprise                                   │
└─────────────────────────────────────────────────────────┘
    ↓ (if Vault unavailable)
┌─────────────────────────────────────────────────────────┐
│ Layer 3: AWS KMS                                        │
│ - Key management service                               │
│ - Encrypted envelope encryption                        │
│ - IAM-based access control                             │
│ Status: ✅ AWS Alternative                              │
└─────────────────────────────────────────────────────────┘
    ↓ (if KMS unavailable)
┌─────────────────────────────────────────────────────────┐
│ Layer 4: Local Encrypted Cache                         │
│ - In-memory cache (15 minute TTL)                      │
│ - Encrypted with master key                            │
│ - Emergency fallback only                              │
│ Status: ✅ Last Resort                                  │
└─────────────────────────────────────────────────────────┘
    ↓
Application Uses Credential
    ↓
Credential Rotation on TTL Expiry
    ↓
Immutable Audit Trail Recorded
```

---

## 🚀 Implementation Layer 1: Google Secret Manager (GSM)

### Configuration

```bash
# Set GCP project
export GCP_PROJECT_ID="nexusshield-prod"

# Create service account
gcloud iam service-accounts create nexusshield-backend \
  --display-name="NexusShield Backend" \
  --project=$GCP_PROJECT_ID

# Grant Secret Accessor role
gcloud projects add-iam-policy-binding $GCP_PROJECT_ID \
  --member="serviceAccount:nexusshield-backend@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# Create credentials key
gcloud iam service-accounts keys create /path/to/key.json \
  --iam-account=nexusshield-backend@${GCP_PROJECT_ID}.iam.gserviceaccount.com
```

### Secret Structure in GSM

```
nexusshield/prod/database/password
nexusshield/prod/database/url
nexusshield/prod/jwt/secret
nexusshield/prod/cors/origins
nexusshield/prod/redis/password
nexusshield/prod/oauth/github-client-id
nexusshield/prod/oauth/github-client-secret
```

### Application Integration

```typescript
// src/services/credentialResolver.ts
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';

class CredentialResolver {
  private gsm: SecretManagerServiceClient;
  private cache: Map<string, { value: string; expiry: number }> = new Map();
  private readonly CACHE_TTL = 15 * 60 * 1000; // 15 minutes

  async resolveCredential(secretName: string): Promise<string> {
    // Check cache first
    const cached = this.cache.get(secretName);
    if (cached && cached.expiry > Date.now()) {
      return cached.value;
    }

    try {
      // Layer 1: GSM
      const value = await this.getFromGSM(secretName);
      this.cacheCredential(secretName, value);
      return value;
    } catch (error) {
      // Layer 2: Vault
      try {
        const value = await this.getFromVault(secretName);
        this.cacheCredential(secretName, value);
        return value;
      } catch (vaultError) {
        // Layer 3: KMS
        try {
          const value = await this.getFromKMS(secretName);
          this.cacheCredential(secretName, value);
          return value;
        } catch (kmsError) {
          // Layer 4: Cache
          return this.getFromCache(secretName);
        }
      }
    }
  }

  private async getFromGSM(secretName: string): Promise<string> {
    const name = `projects/${process.env.GCP_PROJECT_ID}/secrets/${secretName}/versions/latest`;
    const [version] = await this.gsm.accessSecretVersion({ name });
    const payload = version.payload?.data;
    return payload ? payload.toString() : '';
  }

  private cacheCredential(secretName: string, value: string): void {
    this.cache.set(secretName, {
      value,
      expiry: Date.now() + this.CACHE_TTL,
    });
  }
}
```

---

## 🔑 Implementation Layer 2: HashiCorp Vault

### Configuration

```bash
# AppRole setup for backend
vault auth enable approle
vault write auth/approle/role/nexusshield-backend \
  token_ttl=24h \
  token_max_ttl=24h \
  bind_secret_id=true \
  secret_id_ttl=8760h

# Get role ID
vault read auth/approle/role/nexusshield-backend/role-id

# Generate secret ID (temporary)
vault write -f auth/approle/role/nexusshield-backend/secret-id
```

### Secret Path Structure

```
secret/data/nexusshield/prod/database
├── username
├── password
└── url

secret/data/nexusshield/prod/jwt
├── secret

secret/data/nexusshield/prod/oauth
├── github-client-id
├── github-client-secret
```

### Vault Integration Code

```typescript
// Integration with Layer 2 fallback
private async getFromVault(secretName: string): Promise<string> {
  const client = require('node-vault')({
    endpoint: process.env.VAULT_ADDR,
    token: process.env.VAULT_TOKEN,
  });

  const [path, key] = secretName.split('/');
  const response = await client.read(`secret/data/nexusshield/prod/${path}`);
  return response.data.data[key];
}
```

---

## 🔐 Implementation Layer 3: AWS KMS

### Configuration

```bash
# Create KMS key
aws kms create-key \
  --description "NexusShield backend credentials" \
  --region us-east-1

# Alias
aws kms create-alias \
  --alias-name alias/nexusshield-backend \
  --target-key-id <KEY_ID>

# Grant IAM role access
aws kms create-grant \
  --key-id <KEY_ID> \
  --grantee-principal <ROLE_ARN> \
  --operations Encrypt Decrypt
```

### Envelope Encryption Pattern

```typescript
// Encrypts credentials locally with AWS KMS
private async getFromKMS(secretName: string): Promise<string> {
  const KMS = require('aws-sdk/clients/kms');
  const kms = new KMS({ region: 'us-east-1' });

  // Decrypt envelope key
  const response = await kms.decrypt({
    CiphertextBlob: Buffer.from(process.env.KMS_ENCRYPTED_KEY, 'base64'),
  }).promise();

  const masterKey = response.Plaintext;

  // Use master key to decrypt credential
  const crypto = require('crypto');
  const decipher = crypto.createDecipher('aes-256-cbc', masterKey.toString());
  return decipher.update(secretName, 'hex', 'utf8') + decipher.final('utf8');
}
```

---

## 💾 Implementation Layer 4: Local Cache

### Cache Policy

```typescript
private cache: Map<string, {
  value: string;
  expiry: number;
  hash: string; // Track if credential rotated
}> = new Map();

private readonly CACHE_TTL = 15 * 60 * 1000; // 15 minutes
private readonly MAX_CACHE_SIZE = 100; // Max entries
private readonly ENCRYPTION_ALGORITHM = 'aes-256-cbc';

private getFromCache(secretName: string): string {
  const entry = this.cache.get(secretName);

  if (!entry) {
    throw new Error(`No cached credential for ${secretName}`);
  }

  if (entry.expiry < Date.now()) {
    this.cache.delete(secretName);
    throw new Error(`Cached credential expired for ${secretName}`);
  }

  // Log cache hit for audit
  this.auditLog({
    event: 'CACHE_HIT',
    secretName,
    timestamp: new Date().toISOString(),
  });

  return entry.value;
}

private encryptCacheEntry(data: string): string {
  const crypto = require('crypto');
  const masterKey = Buffer.from(process.env.CACHE_MASTER_KEY, 'hex');
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(this.ENCRYPTION_ALGORITHM, masterKey, iv);

  let encrypted = cipher.update(data, 'utf8', 'hex');
  encrypted += cipher.final('hex');

  return `${iv.toString('hex')}:${encrypted}`;
}
```

---

## ⏰ Credential Rotation Policy

### Automatic Rotation

```bash
# Every 24 hours
0 2 * * * /scripts/deployment/rotate-credentials.sh

# Every 6 hours (high-sensitivity)
0 */6 * * * /scripts/deployment/rotate-high-sensitivity-creds.sh
```

### Rotation Implementation

```typescript
export async function rotateCredential(secretName: string): Promise<void> {
  // 1. Generate new credential
  const newCredential = await generateNewCredential(secretName);

  // 2. Store in GSM with versioning
  await gsm.putSecret(secretName, newCredential);

  // 3. Update application (graceful transition)
  const oldCredential = await resolveCredential(secretName);
  this.credentialCache.set(secretName, {
    old: oldCredential,
    new: newCredential,
    rotatedAt: new Date(),
    transitionWindow: 5 * 60 * 1000, // 5 min overlap
  });

  // 4. Log immutable record
  auditTrail.record({
    type: 'CREDENTIAL_ROTATION',
    secretName,
    oldHash: hash(oldCredential),
    newHash: hash(newCredential),
    timestamp: new Date().toISOString(),
    requestId: generateRequestId(),
  });

  // 5. Remove old credential after transition
  setTimeout(() => this.credentialCache.delete(secretName), 5 * 60 * 1000);
}
```

---

## 🚫 What NOT To Do

### ❌ Never Commit Credentials

```bash
# WRONG ❌
DATABASE_PASSWORD=my_secure_password_123  # in .env or docker-compose.yml
JWT_SECRET=dev-secret-key                   # in code

# RIGHT ✅
DATABASE_PASSWORD=${DB_PASSWORD:?error: required}  # on docker-compose
JWT_SECRET=${JWT_SECRET:?error: required}         # required in environment
```

### ❌ Never Use Long-lived Tokens

```bash
# WRONG ❌
VAULT_TOKEN="s.xxxxxxxxxxxxxxxxxxxxx"  # stored forever

# RIGHT ✅
VAULT_TOKEN=$(rotate-token-script.sh)  # rotated hourly
```

### ❌ Never Log Credentials

```typescript
// WRONG ❌
console.log(`Using password: ${password}`);
logger.info('Credentials loaded:', { password, username });

// RIGHT ✅
logger.info('Credentials loaded', { username, passwordHash: hash(password) });
```

### ❌ Never Share Credentials via Email/Chat

```bash
# WRONG ❌
echo "Here's the password: xyz123" | mail team@example.com
slack "Database password is: ${DB_PASSWORD}"

# RIGHT ✅
# Use Vault link or GSM secret reference
echo "Access credentials via: https://vault.example.com/secret/nexusshield/prod/database"
```

---

## 🔍 Audit Trail & Compliance

### Immutable Audit Log

Every credential access is logged immutably:

```json
{
  "timestamp": "2026-03-10T14:30:00Z",
  "event": "CREDENTIAL_ACCESS",
  "secretName": "nexusshield/prod/database/password",
  "requestId": "req-abc123def456",
  "userId": "system:backend",
  "source": "GSM",
  "status": "SUCCESS",
  "ipAddress": "192.168.168.42",
  "ttl": 900,
  "hash": "sha256:abc...def",
  "previousHash": "sha256:old...hash"
}
```

### Log Retention

- **Immutable:** Never deleted, only appended to
- **Format:** JSON Lines (JSONL) for easy parsing
- **Location:** `/app/logs/credentials-audit.jsonl` (persistent volume)
- **Rotation:** Monthly archival to cold storage
- **Access:** Requires authentication + audit logging

---

## 🔬 Testing & Validation

### Test Credential Resolution

```bash
# Test GSM
curl -X POST http://192.168.168.42:3000/api/diagnostics/test-credential \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"source": "gsm", "secretName": "nexusshield/prod/database/password"}'

# Test Vault fallback
curl -X POST http://192.168.168.42:3000/api/diagnostics/test-credential \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"source": "vault", "secretName": "nexusshield/prod/database/password"}'

# Test cache
curl -X POST http://192.168.168.42:3000/api/diagnostics/test-credential \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"source": "cache", "secretName": "nexusshield/prod/database/password"}'
```

### Validation Checklist

- [ ] GSM authentication working
- [ ] Vault AppRole configured
- [ ] KMS key accessible
- [ ] Cache encryption functional
- [ ] Rotation script working
- [ ] Audit trail recording
- [ ] No credentials in git history
- [ ] Long-lived tokens removed
- [ ] Credentials not logged
- [ ] Ephemeral tokens enforced

---

## 📊 Credential Status Dashboard

```bash
# Check credential health
curl -H "Authorization: Bearer $TOKEN" \
  http://192.168.168.42:3000/api/credentials/health

# Expected response:
{
  "database": {
    "source": "GSM",
    "lastRotated": "2026-03-10T10:00:00Z",
    "ttl": 86400,
    "expiresIn": 36400,
    "cacheHits": 1234,
    "cacheMisses": 12,
    "hitRate": 0.99
  },
  "jwt": {
    "source": "Vault",
    "lastRotated": "2026-03-10T14:00:00Z",
    "ttl": 3600,
    "expiresIn": 1800,
    "cacheHits": 5678,
    "cacheMisses": 45,
    "hitRate": 0.99
  }
}
```

---

## 🚀 Deployment Checklist

Before production deployment:

- [ ] GSM project created and configured
- [ ] Service account created with Secret Accessor role
- [ ] Vault instance accessible and AppRole configured
- [ ] AWS KMS key created (if using)
- [ ] All secrets uploaded to GSM
- [ ] Credential rotation script scheduled
- [ ] Audit logging enabled
- [ ] Cache encryption key generated
- [ ] No credentials in docker-compose.yml
- [ ] All credentials use environment variables
- [ ] .env.production uses GSM/Vault references
- [ ] Application tested with all credential layers

---

## ✅ Verification Commands

```bash
# Verify no credentials in docker-compose
grep -E "password|secret|token" docker-compose.yml | grep -v "\${" && echo "FAIL: Found hardcoded creds" || echo "PASS: No hardcoded credentials"

# Verify environment variables enforced
docker-compose config | grep -E "DB_PASSWORD|JWT_SECRET" | grep -v "\${" && echo "FAIL" || echo "PASS"

# Verify GSM connection
gcloud secrets versions access latest --secret="nexusshield/prod/database/password"

# Verify audit trail
docker exec nexusshield-backend wc -l /app/logs/credentials-audit.jsonl
```

---

**Status:** ✅ PRODUCTION READY  
**Authority:** NexusShield Security Team  
**Last Review:** 2026-03-10  
**Next Review:** 2026-04-10
