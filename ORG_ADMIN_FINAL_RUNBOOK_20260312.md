# ORG-ADMIN FINAL RUNBOOK — Remaining Manual Tasks (March 12, 2026)

## Overview
**Status:** 11/14 tasks automated. **3 tasks** require org-admin execution (Cloud Identity, org-policy exceptions).

---

## TASK 7/14: Create `cloud-audit` Cloud Identity Group

**Issue:** #2469  
**Requirement:** Audit logging group for monitoring and compliance.

### Option A: Google Admin Console (Recommended for GUI)
1. Navigate to **Google Admin Console** (admin.google.com)
2. Go to **Groups & Administrators → Groups**
3. Click **Create Group**
4. Fill in:
   - **Group name:** `cloud-audit`
   - **Group email:** `cloud-audit@bioenergystrategies.com`
   - **Description:** `Cloud audit and compliance logging group`
5. Click **Create**
6. Under **Group settings**, add members:
   - `monitoring-uchecker@nexusshield-prod.iam.gserviceaccount.com`
   - `uptime-rotate-sa@nexusshield-prod.iam.gserviceaccount.com`

### Option B: Cloud Identity REST API (Programmatic)
```bash
# Authenticate
gcloud auth login  # Use org admin account if needed

# Get access token
ACCESS_TOKEN=$(gcloud auth print-access-token)
DOMAIN="bioenergystrategies.com"

# Create group
curl -X POST https://cloudidentity.googleapis.com/v1/groups \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"displayName\": \"cloud-audit\",
    \"groupKey\": {
      \"id\": \"cloud-audit@${DOMAIN}\"
    },
    \"labels\": {
      \"cloudidentity.googleapis.com/groups/external_member_restriction\": \"ALLOW_EXTERNAL_MEMBERS\"
    }
  }" | jq .

# Verify creation
curl -X GET "https://cloudidentity.googleapis.com/v1/groups?query=email:cloud-audit@${DOMAIN}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .
```

### Option C: Terraform (Infrastructure as Code)
```hcl
# Add to terraform/google-cloud-identity/main.tf
resource "google_cloud_identity_group" "cloud_audit" {
  display_name = "cloud-audit"
  parent       = "customers/${local.customer_id}"

  group_key {
    id = "cloud-audit@bioenergystrategies.com"
  }

  labels = {
    "cloudidentity.googleapis.com/groups/external_member_restriction" = "ALLOW_EXTERNAL_MEMBERS"
  }
}

resource "google_cloud_identity_group_membership" "monitoring_uchecker" {
  group           = google_cloud_identity_group.cloud_audit.id
  role            = "MEMBER"
  member_key {
    id = "monitoring-uchecker@nexusshield-prod.iam.gserviceaccount.com"
  }
}

resource "google_cloud_identity_group_membership" "uptime_rotate" {
  group           = google_cloud_identity_group.cloud_audit.id
  role            = "MEMBER"
  member_key {
    id = "uptime-rotate-sa@nexusshield-prod.iam.gserviceaccount.com"
  }
}
```

**Verify:**
```bash
gcloud identity groups describe cloud-audit@bioenergystrategies.com
gcloud identity groups members list cloud-audit@bioenergystrategies.com
```

---

## TASK 8/14: Cloud SQL Org Policy Exception

**Issue:** #2345  
**Requirement:** Allow Cloud SQL public IP for specific project.

### Quick Steps (Admin Console)
1. Go to **Google Cloud Console → Org Policies**
2. Search for **`sql.restrictPublicIp`**
3. Click to open policy
4. Click **Manage**
5. In **nexusshield-prod** project row, click **Edit**
6. Select **"Allow all"** or add exception for resource `projects/151423364222/instances/*`
7. Save

### Via gcloud CLI (Faster)
```bash
# Set org ID (replace with actual)
ORG_ID="your-org-id"  # e.g., 123456789

# Create exception for nexusshield-prod
gcloud resource-manager org-policies create sql.restrictPublicIp \
  --project=nexusshield-prod \
  --set-policy - <<EOF
{
  "listPolicy": {
    "allowedValues": [
      "projects/151423364222/instances/*"
    ]
  }
}
EOF

# Verify
gcloud resource-manager org-policies describe sql.restrictPublicIp \
  --project=nexusshield-prod
```

### Via Terraform
```hcl
resource "google_org_policy_policy" "sql_restrict_public_ip" {
  name   = "projects/151423364222/policies/sql.restrictPublicIp"
  parent = "projects/151423364222"

  spec {
    rules {
      allow_all = true
    }
  }
}
```

---

## TASK 10/14: Cloud Monitoring Org Policy (Uptime Checks)

**Issue:** #2488  
**Requirement:** Allow uptime check policy exceptions.

### Quick Steps (Admin Console)
1. Go to **Google Cloud Console → Org Policies**
2. Search for **`monitoring.disableAlertPolicies`**
3. Open and click **Manage**
4. For **nexusshield-prod**, add exception:
   - Resource: `projects/151423364222`
   - Exception type: **Allow**
5. Save

### Via gcloud CLI
```bash
gcloud resource-manager org-policies create monitoring.disableAlertPolicies \
  --project=nexusshield-prod \
  --set-policy - <<EOF
{
  "listPolicy": {
    "allowedValues": [
      "projects/151423364222"
    ]
  }
}
EOF

# Verify
gcloud resource-manager org-policies describe monitoring.disableAlertPolicies \
  --project=nexusshield-prod
```

### Via Terraform
```hcl
resource "google_org_policy_policy" "monitoring_disable_alert" {
  name   = "projects/151423364222/policies/monitoring.disableAlertPolicies"
  parent = "projects/151423364222"

  spec {
    rules {
      allow_all = true
    }
  }
}
```

---

## TASK 9/14: Cloud SQL Auth Proxy (K8s Sidecar)

**Issue:** #2349  
**Requirement:** Enable Cloud SQL Auth Proxy in Kubernetes for secure DB access.

### Update Pod Spec (e.g., `k8s/deployment.yaml`)
```yaml
spec:
  containers:
  - name: app
    image: gcr.io/nexusshield-prod/backend:latest
    ports:
    - containerPort: 8080
    env:
    - name: CLOUDSQL_INSTANCE
      value: "nexusshield-prod:us-central1:prod-db"
    - name: DB_HOST
      value: "127.0.0.1:5432"
  
  # Add Cloud SQL Auth Proxy sidecar
  - name: cloud-sql-proxy
    image: gcr.io/cloudsql-docker/gce-proxy:1.33.2-alpine
    command:
      - "/cloud_sql_proxy"
      - "-ip_address_types=PRIVATE"
      - "-instances=nexusshield-prod:us-central1:prod-db=tcp:5432"
    securityContext:
      runAsNonRoot: true
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "250m"

  serviceAccountName: deployer-run
  automountServiceAccountToken: true
```

### Verify Workload Identity
```bash
kubectl get serviceaccount deployer-run -o yaml | grep -i annotation

# Should show:
# iam.gke.io/gcp-service-account: deployer-run@nexusshield-prod.iam.gserviceaccount.com
```

---

## Execution Checklist

- [ ] **Task 7:** Create `cloud-audit` group (Option A/B/C)
- [ ] **Task 8:** Apply Cloud SQL org policy exception
- [ ] **Task 10:** Apply monitoring org policy exception
- [ ] **Task 9:** Deploy Cloud SQL Auth Proxy sidecar to K8s
- [ ] **Verify:** Run `bash scripts/ops/production-verification.sh`
- [ ] **Commit:** `git add -A && git commit -m "chore: org-admin tasks completion 20260312"`

---

## Support

For issues with:
- **Cloud Identity:** Check org admin permissions; ensure Cloud Identity API is enabled
- **Org Policies:** Verify org-level IAM (Organization Admin role required)
- **Cloud SQL Proxy:** Confirm Workload Identity binding using `kubectl logs <pod> -c cloud-sql-proxy`

---

*Generated: March 12, 2026 | Version: 1.0*
