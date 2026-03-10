# Infrastructure Deployment Status - March 10, 2026

## 🚨 BLOCKED BY ORG POLICY - ESCALATION REQUIRED

**Current Status**: Production infrastructure deployment **HALTED** due to GCP organization policies blocking Cloud SQL IP assignment.

**Resolution**: Requires GCP Organization Admin to exempt `nexusshield-prod` project from VPC peering and public IP constraints.

---

## Deployment Summary

### Infrastructure Planned
- ✅ **Cloud Run** - Containerized backend API service
- ❌ **Cloud SQL** - PostgreSQL database (BLOCKED - no IP assignment possible)
- ✅ **GCP Services** - VPC, Secret Manager, IAM, Artifact Registry
- ✅ **Automation** - Terraform IaC with local backend
- ✅ **Security** - Service accounts, IAM roles, SSL/TLS enforcement

### What Was Successfully Deployed
1. **GCP VPC Network** (`nexusshield-vpc`)
   - Status: ✅ Created
   - Region: `us-central1`
   - CIDR: `10.0.0.0/16`

2. **VPC Subnet** (`nexusshield-subnet-us-central1`)
   - Status: ✅ Created
   - Private IP Google Access enabled
   - Flow logs configured

3. **Service Account** (`nxs-portal-production@nexusshield-prod.iam.gserviceaccount.com`)
   - Status: ✅ Created
   - Roles granted:
     - `roles/logging.logWriter`
     - `roles/secretmanager.secretAccessor`
     - `roles/cloudsql.client`
     - `roles/compute.networkUser`
     - `roles/run.invoker`
     - `roles/artifactregistry.reader`

4. **Secret Manager** (database credentials)
   - Status: ✅ Credentials created
   - Auto-rotation enabled

5. **Artifact Registry** (`portal-backend-repo`)
   - Status: ✅ Created
   - Docker format enabled
   - Location: `us-central1`

---

## 🛑 **BLOCKER: Cloud SQL** - CANNOT PROCEED

### Problem
Two contradictory org policies prevent Cloud SQL from being assigned ANY IP address:

#### **Policy 1: `constraints/compute.restrictVpcPeering`** ❌
Blocks **Private IP via Private Service Connect**

Error during terraform apply:
```
Error waiting for Create Service Networking Connection: 
Constraint constraints/compute.restrictVpcPeering violated for project 151423364222. 
Peering the network projects/a4d0e081639952a26p-tp/global/networks/servicenetworking 
is not allowed.
```

#### **Policy 2: `constraints/sql.restrictPublicIp`** ❌
Blocks **Public IP allocation**

Error during terraform apply:
```
Error, failed to create instance nexusshield-portal-db-e67c: 
googleapi: Error 400: Organization Policy check failure: 
the external IP of this instance violates the constraints/sql.restrictPublicIp 
enforced at the 151423364222 project
```

### Impact
- ❌ Cloud SQL PostgreSQL instance cannot be created
- ❌ Cloud Run backend cannot connect to database
- ❌ Application has no persistent storage
- ❌ Production go-live blocked

---

## Deployment Artifacts

### Terraform Configuration
**File**: `/nexusshield/infrastructure/terraform/production/main.tf`

**Key resources**:
```hcl
# Network
resource "google_compute_network" "portal_vpc" { ... }           # ✅ Created
resource "google_compute_subnetwork" "private_subnet" { ... }   # ✅ Created

# Database (BLOCKED)
resource "google_sql_database_instance" "portal_db" { ... }      # ❌ Failed at apply
resource "google_sql_database" "portal_db_schema" { ... }        # ⏹️ Pending
resource "google_sql_user" "portal_db_user" { ... }              # ⏹️ Pending

# Compute
resource "google_cloud_run_service" "portal_backend" { ... }     # ⏹️ Pending (waiting for DB)

# Security
resource "google_service_account" "portal_backend" { ... }       # ✅ Created
resource "google_project_iam_member" "*" { ... }                 # ✅ 5 members created
```

### Deployment State
- **Backend**: Local (`terraform.tfstate`)
- **Location**: `/nexusshield/infrastructure/terraform/production/`
- **Service Account**: `terraform-deployer@nexusshield-prod.iam.gserviceaccount.com`
- **Project**: `nexusshield-prod` (151423364222)

### Recent Commits
1. `4308f51e8` - Document org policy blocker (2026-03-10)
2. Previously: Infrastructure setup, service account creation

### Logs
- Plan: `/nexusshield/infrastructure/terraform/production/tfplan.production.public`
- Apply logs:
  - `/nexusshield/infrastructure/terraform/production/terraform-apply-production-20260310-031213.log` (first attempt, PSC failed)
  - `/nexusshield/infrastructure/terraform/production/terraform-apply-public-20260310-031530.log` (public IP attempt, blocked)

---

## Escalation Path

### Required Action
**GCP Organization Admin must**:
1. Review org policy `constraints/compute.restrictVpcPeering`
   - Add `nexusshield-prod` project to exclusion list, OR
   - Modify policy to allow Cloud SQL PSC connections

2. Review org policy `constraints/sql.restrictPublicIp`
   - Add `nexusshield-prod` project to exclusion list, OR
   - Modify policy to allow public IP for database instance

3. Confirm policy changes take effect

### Re-deployment Steps (After Policy Resolution)
```bash
cd /nexusshield/infrastructure/terraform/production
export GOOGLE_APPLICATION_CREDENTIALS=/tmp/terraform-sa.json
terraform plan -out=tfplan.final
terraform apply tfplan.final
```

### Verification Steps
```bash
# Verify Cloud SQL instance is created
gcloud sql instances list --project=nexusshield-prod

# Verify Cloud Run service has database connection
gcloud run services describe portal-backend --region=us-central1 --project=nexusshield-prod

# Run health checks
bash ../../../scripts/phase6-health-check.sh
```

---

## Alternative Options (If Policies Cannot Be Changed)

### Option 1: Firestore/Datastore
- Migrate Portal MVP to use Cloud Firestore (NoSQL)
- No IP assignment constraints
- Requires code changes to backend

### Option 2: Alternative Project
- Deploy to test/staging GCP project without these constraints
- Use for development/testing until production policies updated

### Option 3: Cloud Endpoints
- Use managed API endpoints instead of direct Cloud SQL access
- Add additional abstraction layer

---

## GitHub Issue
**Issue**: [#2234 - BLOCKER: GCP Organization Policies Preventing Production Deployment](https://github.com/kushin77/self-hosted-runner/issues/2234)

**Labels**: `blocker`, `org-policy`, `infrastructure`, `production`, `iam`

---

## Timeline
- **2026-03-10 00:00**: Deployment attempt started
- **2026-03-10 03:12**: PSC (Private Service Connect) blocker identified
- **2026-03-10 03:15**: Public IP alternative attempted - also blocked
- **2026-03-10 03:18**: Org policy constraints documented
- **2026-03-10 03:19**: Escalation issue #2234 created

---

## Notes for Org Admin

### Required IAM Roles for Exemption
Whoever applies the policy changes needs:
- `roles/resourcemanager.organizationAdmin`
- `roles/compute.networkAdmin`
- `roles/cloudsql.admin`

### Configuration Examples
**For Private Service Connection (PSC)**:
```yaml
ListPolicy (constraints/compute.restrictVpcPeering):
  denied_values: []  # Allow all VPC peering
  # OR
  ListPolicy:
    deniedValues:
      - "projects/{OTHER_PROJECT}"
    allowedValues:
      - "projects/nexusshield-prod"
```

**For Public IP**:
```yaml
ListPolicy (constraints/sql.restrictPublicIp):
  denied_values: []  # Allow public IPs
  # OR
  BooleanPolicy:
    enforced: false  # Disable constraint
```

---

**Deployment Awaiting**: Org Policy Resolution  
**Go-Live Date**: Pending exemption approval  
**Contact**: DevOps / Infrastructure Team  
**Last Updated**: 2026-03-10 03:19 UTC
