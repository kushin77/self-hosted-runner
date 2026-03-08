# 🚀 QUICK START - Operator Provisioning Guide

**Time Required**: 35-95 minutes | **Complexity**: Low | **Automation**: 100%

---

## ⚡ FASTEST PATH (Use the Helper Tool)

### 1. Run the Provisioning Helper
```bash
cd /path/to/self-hosted-runner
./scripts/automation/operator-provisioning-helper.sh
```

**What you'll see:**
```
Select provisioning task:
  1) Bring staging cluster online (K3s)
  2) Provision GCP Workload Identity (OIDC)
  3) Provision AWS OIDC Role
  4) Set GitHub secrets for provisioning
  5) Verify all provisioning steps
  6) Full provisioning flow (all steps)
  0) Exit
```

### 2. Choose "6" (Full Provisioning Flow)

The helper will guide you through:
- ✅ Cluster recovery (automated)
- ✅ GCP setup (guided, ~10 min)
- ✅ AWS setup (guided, ~10 min)
- ✅ Secret provisioning (automatic)
- ✅ Verification (automated)

---

## 📋 MANUAL PATH (If Helper Doesn't Work)

### Step 1: Bring Staging Cluster Online (10 min)
```bash
# SSH into the staging cluster and start k3s
ssh admin@192.168.168.42 systemctl status k3s
ssh admin@192.168.168.42 systemctl start k3s  # if stopped

# Verify it's online
timeout 5 bash -c "echo >/dev/tcp/192.168.168.42/6443" && echo "✅ Online"
```

### Step 2: GCP Workload Identity (10 min)
```bash
# Set these variables
export GCP_PROJECT_ID="your-project-id"
export GCP_SERVICE_ACCOUNT="terraform@your-project-id.iam.gserviceaccount.com"

# Create workload identity
gcloud services enable iamcredentials.googleapis.com cloudresourcemanager.googleapis.com --project="$GCP_PROJECT_ID"

gcloud iam workload-identity-pools create github-actions \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --display-name="GitHub Actions"

gcloud iam workload-identity-pools providers create-oidc github-provider \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="github-actions" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.aud=assertion.aud" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant service account permissions
gcloud iam service-accounts add-iam-policy-binding "$GCP_SERVICE_ACCOUNT" \
  --project="$GCP_PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/$GCP_PROJECT_ID/locations/global/workloadIdentityPools/github-actions/attribute.aud/*"

# Get provider URL
PROVIDER_URL=$(gcloud iam workload-identity-pools describe github-actions \
  --project="$GCP_PROJECT_ID" \
  --location="global" \
  --format="value(name)")

echo "Save this: $PROVIDER_URL"
```

### Step 3: AWS OIDC Role (10 min)
```bash
# Set these variables
export AWS_ACCOUNT_ID="123456789012"
export GITHUB_REPO="kushin77/self-hosted-runner"

# Create Workload Identity Provider
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" || echo "Provider exists"

# Create IAM role with trust relationship
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::AWS_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:GITHUB_REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
EOF

sed -i "s/AWS_ACCOUNT_ID/$AWS_ACCOUNT_ID/g" /tmp/trust-policy.json
sed -i "s|GITHUB_REPO|$GITHUB_REPO|g" /tmp/trust-policy.json

aws iam create-role \
  --role-name github-actions-terraform \
  --assume-role-policy-document file:///tmp/trust-policy.json || echo "Role exists"

# Attach permissions
aws iam attach-role-policy \
  --role-name github-actions-terraform \
  --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

echo "Save this: arn:aws:iam::$AWS_ACCOUNT_ID:role/github-actions-terraform"
```

### Step 4: Set GitHub Secrets (5 min)
```bash
# From GCP step, you have: $PROVIDER_URL
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER < <(echo "$PROVIDER_URL")

# From AWS step, you have the role ARN
gh secret set AWS_OIDC_ROLE_ARN < <(echo "arn:aws:iam::$AWS_ACCOUNT_ID:role/github-actions-terraform")
gh secret set USE_OIDC < <(echo "true")

# Optional: Set AWS Spot credentials
gh secret set AWS_ROLE_TO_ASSUME < <(echo "arn:aws:iam::$AWS_ACCOUNT_ID:role/YOUR_SPOT_ROLE")
gh secret set AWS_REGION < <(echo "us-east-1")

# Set kubeconfig (if you have it)
gh secret set STAGING_KUBECONFIG < ~/.kube/config-staging.yaml
```

---

## ✅ VERIFICATION

### Run the Readiness Check
```bash
./scripts/automation/deployment-readiness-validator.sh
```

Expected output:
```
✓ Staging cluster online (192.168.168.42:6443)
✓ Secret found: AWS_OIDC_ROLE_ARN
✓ Secret found: USE_OIDC
✓ Secret found: GCP_WORKLOAD_IDENTITY_PROVIDER
✓ Workflow exists: phase-p4-terraform-apply-orchestrator
[...]
✅ DEPLOYMENT READY
```

### Or Monitor Automatically
Watch issue #231 - every 30 minutes, the system checks readiness and posts updates.

---

## 🤖 WHAT HAPPENS AFTER YOU COMPLETE PROVISIONING

1. **Automation detects** your actions (~2 minutes)
2. **Auto-posts** confirmation to issue #231
3. **Auto-triggers** Phase P4 deployment
4. **Infrastructure deploys** automatically (~15 minutes via terraform)
5. **Phase P5 validates** the deployment
6. **Complete infrastructure** is ready ✅

---

## 🆘 TROUBLESHOOTING

### Cluster Still Offline?
```bash
# Check k3s status
ssh admin@192.168.168.42 systemctl status k3s --full

# Check logs
ssh admin@192.168.168.42 journalctl -u k3s -n 50

# Restart manually
ssh admin@192.168.168.42 systemctl restart k3s
```

### GCP Setup Failing?
```bash
# Verify gcloud is installed
gcloud --version

# Check authentication
gcloud auth list

# Verify project
gcloud config get-value project
```

### AWS Setup Failing?
```bash
# Check AWS CLI
aws sts get-caller-identity

# Check OIDC provider exists
aws iam list-open-id-connect-providers

# Verify role
aws iam get-role --role-name github-actions-terraform
```

### GitHub Secrets Not Set?
```bash
# List all secrets
gh secret list --repo kushin77/self-hosted-runner

# Verify specific secret
gh secret get AWS_OIDC_ROLE_ARN --repo kushin77/self-hosted-runner
```

---

## ⏱️ TIME BREAKDOWN

| Task | Time | Parallelizable |
|------|------|-----------------|
| Cluster recovery | 10 min | ✅ Yes |
| GCP OIDC setup | 10 min | ✅ Yes |
| AWS OIDC setup | 10 min | ✅ Yes |
| GitHub secrets | 5 min | ✅ Yes |
| **Total** | **35 min** (parallel) or **95 min** (sequential) | |

**Recommended**: Run in parallel where possible = **35 min total**

---

## 📞 SUPPORT

### Automated Monitoring
- Issue #231: OPS blocker status (every 15 min)
- Issue #220: Phase P5 validation (every 30 min)

### Manual Verification
```bash
# Full status
./scripts/automation/infrastructure-readiness.sh

# Blocker check
./scripts/automation/ops-blocker-automation.sh

# Readiness check
./scripts/automation/deployment-readiness-validator.sh
```

---

## 🎯 SUCCESS INDICATORS

✅ **You're done when:**
- Cluster is online (can SSH, k3s responding)
- All GitHub secrets are set (verify with `gh secret list`)
- Readiness check shows "DEPLOYMENT READY" (90%+ score)
- System auto-posts "Deployment prerequisites detected" to issue #231

Then just **wait** - the system will deploy everything automatically! ✨

---

**Questions?** Check the detailed docs:
- [OPERATOR_EXECUTION_SUMMARY.md](./OPERATOR_EXECUTION_SUMMARY.md)
- [FULL_AUTOMATION_DELIVERY_FINAL.md](./FULL_AUTOMATION_DELIVERY_FINAL.md)
