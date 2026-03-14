# SSO Platform - Complete Operations & API Reference

## Quick Start

### 1. Deploy Complete Platform
```bash
# Ensure GKE cluster is running
gcloud container clusters describe nexus-prod-gke --zone=us-central1-a

# Execute deployment orchestrator
chmod +x scripts/sso/deploy-complete-sso-platform.sh
./scripts/sso/deploy-complete-sso-platform.sh nexus-prod us-central1-a

# Wait for all pods to stabilize (5-10 minutes)
kubectl get pods -n keycloak -w
```

### 2. Access Services
```bash
# Grafana dashboards
kubectl port-forward -n keycloak svc/grafana 3000:80 &
# Open http://localhost:3000 (admin / check secret for password)

# Prometheus metrics
kubectl port-forward -n keycloak svc/prometheus 9090:90 &
# Open http://localhost:9090

# Keycloak admin console
kubectl port-forward -n keycloak svc/keycloak 8080:8080 &
# Open http://localhost:8080/auth/admin (admin / check secret)
```

### 3. Run Tests
```bash
# Integration tests (10 categories)
./scripts/testing/integration-tests.sh

# Load testing with k6
k6 run scripts/testing/load-test-k6.js
```

## Client Integration

### JavaScript/React
```javascript
// Install
npm install @nexus/sso-client

// Usage
import { useSSOAuth } from '@nexus/sso-client';

function App() {
  const { user, login, logout, token } = useSSOAuth({
    clientId: 'web-app',
    redirectUri: 'http://localhost:3000/callback',
  });

  return (
    <div>
      {user ? (
        <>
          <p>Welcome, {user.name}</p>
          <button onClick={logout}>Logout</button>
        </>
      ) : (
        <button onClick={login}>Login</button>
      )}
    </div>
  );
}
```

### Python/FastAPI
```python
# Install
pip install nexus-sso-client

# Usage
from fastapi import FastAPI
from nexus_sso import require_auth, get_user_info

app = FastAPI()

@app.get("/api/user")
@require_auth
async def get_user(token: str):
    user = await get_user_info(token)
    return user
```

### Go/Gin
```go
// Install
go get github.com/nexus/sso-client-go

// Usage
import "github.com/nexus/sso-client-go"

func main() {
  auth := sso.NewAuthMiddleware(&sso.Config{
    ClientID: "api-server",
    IssuerURL: "https://keycloak.nexus.local",
  })

  router.Use(auth.Middleware())
}
```

## Core API Endpoints

### Authentication
```bash
# OAuth2 Authorization Endpoint
GET /auth/realms/master/protocol/openid-connect/auth
  ?client_id=web-app
  &redirect_uri=https://app.example.com/callback
  &response_type=code
  &scope=openid profile email

# Token Exchange
POST /auth/realms/master/protocol/openid-connect/token
  -d "grant_type=authorization_code"
  -d "code=AUTH_CODE"
  -d "client_id=web-app"
  -d "client_secret=SECRET"

# Refresh Token
POST /auth/realms/master/protocol/openid-connect/token
  -d "grant_type=refresh_token"
  -d "refresh_token=REFRESH_TOKEN"
  -d "client_id=web-app"
  -d "client_secret=SECRET"

# OIDC Discovery
GET /.well-known/openid-configuration

# User Info
GET /auth/realms/master/protocol/openid-connect/userinfo
  -H "Authorization: Bearer ACCESS_TOKEN"

# Logout
POST /auth/realms/master/protocol/openid-connect/logout
  -d "id_token_hint=ID_TOKEN"
  -d "post_logout_redirect_uri=https://app.example.com"
```

### User Management
```bash
# Get all users
GET /auth/admin/realms/master/users
  -H "Authorization: Bearer ADMIN_TOKEN"

# Create user
POST /auth/admin/realms/master/users
  -H "Authorization: Bearer ADMIN_TOKEN"
  -d '{
    "username": "john.doe",
    "email": "john@example.com",
    "enabled": true
  }'

# Assign roles to user
POST /auth/admin/realms/master/users/{userId}/role-mappings/realm
  -H "Authorization: Bearer ADMIN_TOKEN"
  -d '[{"id":"ROLE_ID","name":"admin"}]'

# Reset user password
PUT /auth/admin/realms/master/users/{userId}/reset-password
  -H "Authorization: Bearer ADMIN_TOKEN"
  -d '{
    "type": "password",
    "temporary": false,
    "value": "NewPassword123!"
  }'
```

## Operations Guide

### Cluster Monitoring
```bash
# Real-time pod status
kubectl get pods -n keycloak -w

# Resource utilization
kubectl top nodes
kubectl top pods -n keycloak --sort-by=memory

# Event monitoring
kubectl get events -n keycloak --sort-by='.lastTimestamp'

# Pod logs
kubectl logs -n keycloak keycloak-0 --tail=100 -f
```

### Database Management
```bash
# Connect to PostgreSQL primary
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak

# Backup database
./scripts/sso/backup-restore-procedures.sh backup

# Restore from backup
./scripts/sso/backup-restore-procedures.sh restore keycloak_backup_20260314_010000.sql.gz

# List available backups
./scripts/sso/backup-restore-procedures.sh list

# Monitor replication status
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak \
  -c "SELECT * FROM pg_stat_replication;"
```

### Cache Management
```bash
# Connect to Redis
kubectl run -it --rm redis-cli --image=redis --restart=Never \
  -n keycloak -- \
  redis-cli -h redis-cluster.keycloak.svc.cluster.local -p 6379

# Check cache status
> CLUSTER INFO
> INFO stats

# Clear all cache
> FLUSHALL

# Monitor cache access
> MONITOR
```

### Scaling
```bash
# Scale Keycloak replicas
kubectl scale deployment keycloak -n keycloak --replicas=5

# Scale OAuth2-Proxy replicas
kubectl scale deployment oauth2-proxy -n oauth2-proxy --replicas=3

# Verify auto-scaling metrics
kubectl get hpa -n keycloak
kubectl describe hpa keycloak-autoscaler -n keycloak

# Manual patch for autoscaler
kubectl patch hpa keycloak-autoscaler -n keycloak \
  -p '{"spec":{"minReplicas":3,"maxReplicas":10}}'
```

### Backup & Restore
```bash
# Manual backup
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  /bin/bash -c 'PGPASSWORD=$POSTGRES_PASSWORD pg_dump -U keycloak keycloak' \
  | gzip > keycloak_backup_$(date +%s).sql.gz

# Upload to GCS
gsutil cp keycloak_backup_*.sql.gz gs://nexus-prod-backups/sso/

# Restore from GCS backup
gsutil cp gs://nexus-prod-backups/sso/keycloak_backup_*.sql.gz . && \
  gunzip -c keycloak_backup_*.sql.gz | \
  kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$POSTGRES_PASSWORD psql -U keycloak keycloak
```

## Troubleshooting

### Keycloak Not Starting
```bash
# Check pod logs
kubectl logs keycloak-0 -n keycloak -f

# Common issues:
# 1. Database not ready - wait for keycloak-postgres-0 to be Running
# 2. PVC not provisioning - check GKE quota
# 3. Network policy blocking - verify network policies allow egress to DB

# Solutions:
kubectl describe pod keycloak-0 -n keycloak
kubectl get pvc -n keycloak
kubectl get networkpolicy -n keycloak
```

### OAuth2-Proxy Token Validation Failures
```bash
# Check OAuth2-Proxy logs
kubectl logs -n oauth2-proxy oauth2-proxy-0 -f

# Verify it can reach Keycloak
kubectl run -it --rm debug --image=busybox --restart=Never \
  -n oauth2-proxy -- \
  wget -O- http://keycloak.keycloak.svc.cluster.local:8080/auth/health

# Check client credentials
kubectl get secret oauth2-proxy-config -n oauth2-proxy -o yaml
```

### Database Replication Lag
```bash
# Monitor replication lag
kubectl exec -it keycloak-postgres-0 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak \
  -c "SELECT client_addr, write_lag, flush_lag, replay_lag FROM pg_stat_replication;"

# If lag > 1s:
# 1. Check network bandwidth: kubectl top nodes
# 2. Check replica disk I/O: kubectl exec keycloak-postgres-1 -- iostat
# 3. Increase max_wal_senders if needed
```

### Cache Hit Rate Low (<80%)
```bash
# Check Redis memory usage
kubectl exec -it redis-cluster-0 -n keycloak -- redis-cli INFO memory

# If memory > 90% full:
# 1. Increase Redis memory limit in 11-redis-cache-layer.yaml
# 2. Adjust LRU eviction policy: redis-cli CONFIG SET maxmemory-policy allkeys-lru
# 3. Increase token TTL to reduce cache churn
```

## Troubleshooting Integration Tests
```bash
# Run tests with debug output
VERBOSE=1 bash -x ./scripts/testing/integration-tests.sh

# Test specific component
./scripts/testing/integration-tests.sh --filter="keycloak"
./scripts/testing/integration-tests.sh --filter="oauth2"
./scripts/testing/integration-tests.sh --filter="database"
```

## Advanced Configuration

### SAML 2.0 Integration
```bash
# Future: Create TIER 4 manifests
# Will support SAML identity providers and service providers
cat > infrastructure/sso/13-saml-configuration.yaml << EOF
apiVersion: keycloak.org/v1alpha1
kind: KeycloakClient
metadata:
  name: saml-client
  namespace: keycloak
spec:
  realmSelector:
    matchLabels:
      realm: master
  client:
    clientId: urn:example:app
    protocol: saml
    redirectUris:
      - "https://app.example.com/acs"
EOF
```

### LDAP Federation
```bash
# Future: Configure LDAP user federation
# Will sync users from corporate LDAP directory
kubectl apply -f infrastructure/sso/ldap-federation.yaml
```

### Multi-Tenancy
```bash
# Create additional realms for different tenants
POST /auth/admin/realms
  -d '{
    "realm": "tenant-acme",
    "enabled": true,
    "displayNameHtml": "ACME Corporation"
  }'
```

## Performance Tuning

### Keycloak JVM Tuning
```yaml
# Edit keycloak deployment
kubectl edit deployment keycloak -n keycloak

# Key JVM settings:
env:
  - name: JAVA_OPTS_APPEND
    value: "-Xmx2g -Xms2g -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
```

### Database Query Optimization
```sql
-- Enable query logging
ALTER SYSTEM SET log_min_duration_statement = 1000;
SELECT pg_reload_conf();

-- Check slow queries
SELECT query, calls, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;
```

### Network Performance
```bash
# Check Pod-to-Pod latency
kubectl run -it --rm latency-test --image=nicolaka/netshoot --restart=Never \
  -n keycloak -- \
  ping -c 5 redis-cluster.keycloak.svc.cluster.local
```

## Compliance & Audit

### Audit Trail
```bash
# Export audit logs
./scripts/sso/compliance-audit-export.sh export

# Check audit data
kubectl logs -n keycloak -l app=jaeger-collector | grep "audit"
```

### GDPR Data Deletion
```bash
# Export user data
./scripts/sso/compliance-audit-export.sh gdpr-export user-id

# Delete user data
./scripts/sso/compliance-audit-export.sh gdpr-delete user-id
```

### PCI DSS Compliance
```bash
# Verify encryption in transit
kubectl get secret -n keycloak | grep tls

# Verify encryption at rest
kubectl get secret keycloak-postgres -n keycloak \
  -o jsonpath='{.metadata.annotations.encryption\.gcp\.io/key}'
```

## Cost Optimization

### Reserved Capacity
```bash
# Using GKE with reserved instances
gcloud compute reservations create sso-reservation \
  --zone=us-central1-a \
  --vm-count=3 \
  --machine-type=n1-standard-4

# Bind cluster to reservation
gcloud container clusters update nexus-prod-gke \
  --zone=us-central1-a \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=10
```

### Pod Disruption Budgets
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: keycloak-pdb
  namespace: keycloak
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: keycloak
```

## Disaster Recovery

### RTO/RPO Targets
- **RTO** (Recovery Time Objective): < 15 minutes
- **RPO** (Recovery Point Objective): < 1 hour

### Backup Strategy
- Daily automated backups to GCS
- 30-day retention
- Point-in-time recovery via WAL archiving
- Cross-region replication for critical data

### Failover Procedure
```bash
# 1. Detect primary PostgreSQL failure
kubectl exec -it keycloak-postgres-1 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak \
  -c "SELECT * FROM pg_stat_replication;"

# 2. Promote standby manually if needed
kubectl exec -it keycloak-postgres-1 -n keycloak -- \
  PGPASSWORD=$(kubectl get secret keycloak-postgres -n keycloak \
    -o jsonpath='{.data.password}' | base64 -d) \
  psql -U keycloak -d keycloak \
  -c "SELECT pg_promote();"

# 3. Verify failover succeeded
kubectl get pods -n keycloak -l app=keycloak-postgres
```

---

**Documentation Version**: 1.0.0  
**Last Updated**: 2026-03-14  
**Status**: Production Ready  
**Support**: ops@nexus.local
