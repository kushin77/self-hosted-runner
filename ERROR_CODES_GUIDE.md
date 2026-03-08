# Error Codes & Troubleshooting Guide

**Last Updated**: March 7, 2026  
**Status**: 🚨 Structured Error Reference (Common + Advanced)  
**Purpose**: Quickly identify, diagnose, and resolve errors in workflows and operations

---

## Quick Navigation

- [Common Errors](#common-errors) - Most frequently occurring
- [By System](#errors-by-system) - Grouped by infrastructure component
- [By Symptom](#errors-by-symptom) - When you see X, check Y
- [Error Code Reference](#error-code-reference) - Complete code definitions
- [Debugging Tools](#debugging-tools) - Commands to diagnose issues

---

## Common Errors

### **ERR-AWS-001: AWS OIDC Token Exchange Failed**

**Symptom:**
```
Error: OIDC token exchange failed: 403 Unauthorized
Failed to assume AWS role
```

**Root Causes:**
1. `AWS_OIDC_ROLE_ARN` secret not set
2. GitHub OIDC certificate not trusted by AWS
3. Service account has wrong permissions
4. Reached token creation limit

**Quick Diagnosis:**
```bash
# Check if secret exists
gh secret list --repo kushin77/self-hosted-runner | grep AWS_OIDC

# Verify role exists
aws iam get-role --role-name github-actions-terraform

# Check trust policy
aws iam get-role --role-name github-actions-terraform --query Role.AssumeRolePolicyDocument
```

**Solutions:**
| Solution | Steps | Time |
|----------|-------|------|
| **Set AWS_OIDC_ROLE_ARN** | `gh secret set AWS_OIDC_ROLE_ARN` | 1 min |
| **Fix trust policy** | See: [AWS_OIDC_SETUP.md](docs/AWS_OIDC_SETUP.md) | 5 min |
| **Add permissions** | `aws iam attach-role-policy ...` | 2 min |
| **Wait for token Reset** | Certificate refresh (4 hours auto) | 4 hrs |

**Workflow to Check:**
- `terraform-auto-apply.yml`
- `cloud-ops-bootstrap.yml`
- `elasticache-apply-safe.yml`

---

### **ERR-GCP-001: GCP Workload Identity Token Exchange Failed**

**Symptom:**
```
Error: failed to get ID token from GCP: invalid credential
google: could not find default credentials
```

**Root Causes:**
1. `GCP_WORKLOAD_IDENTITY_PROVIDER` not set
2. Workload identity pool not configured
3. Service account lacks required permissions
4. OIDC provider not setup in GCP

**Quick Diagnosis:**
```bash
# Check secrets
gh secret list | grep GCP_

# Verify workload pool exists
gcloud iam workload-identity-pools list --location=global --project=gcp-eiq

# Check OIDC provider
gcloud iam workload-identity-pools providers describe github \
  --location=global --workload-identity-pool=github-actions \
  --project=gcp-eiq
```

**Solutions:**
| Solution | Steps | Time |
|----------|-------|------|
| **Set GCP secrets** | `gh secret set GCP_PROJECT_ID ...` | 3 min |
| **Setup workload pool** | See: [GSM_AWS_CREDENTIALS_QUICK_START.md](GSM_AWS_CREDENTIALS_QUICK_START.md) | 8 min |
| **Fix service account** | `gcloud iam service-accounts create ...` | 3 min |

**Related Docs:**
- [GCP_PERMISSION_VALIDATOR.md](docs/GCP_PERMISSION_VALIDATOR.md)
- [GSM_AWS_CREDENTIALS_VERIFICATION.md](GSM_AWS_CREDENTIALS_VERIFICATION.md)

---

### **ERR-TERRAFORM-001: Terraform State Lock Timeout**

**Symptom:**
```
Error: Error acquiring the state lock
Error: error acquiring the state lock: ConflictException: Resource is locked
```

**Root Causes:**
1. Previous terraform apply still running
2. State lock file stuck (crashed process didn't cleanup)
3. Multiple concurrent terraform runs
4. DynamoDB table throttled (rate limit)

**Quick Diagnosis:**
```bash
# Check lock in AWS
aws dynamodb get-item \
  --table-name terraform-lock \
  --key '{"LockID": {"S": "s3-bucket/terraform.tfstate"}}'

# List running terraform processes
ps aux | grep terraform | grep -v grep

# Check workflow run status
gh run list --repo kushin77/self-hosted-runner | grep terraform
```

**Solutions:**
| Solution | Steps | Time |
|----------|-------|------|
| **Wait for lock** | Wait 5-10 minutes for timeout | 10 min |
| **Force unlock** | `terraform force-unlock LOCK_ID` | 1 min (⚠️ risky) |
| **Cancel stuck run** | `gh run cancel <RUN_ID>` | 2 min |
| **Clear DynamoDB lock** | AWS CLI manual delete | 2 min |

**Prevention:**
- Use: `terraform-auto-apply.yml` (has lock timeout of 20min)
- Avoid: Multiple concurrent terraform applies
- Monitor: `terraform-phase2-drift-detection.yml` for drift

---

### **ERR-RUNNER-001: Self-Hosted Runner Offline**

**Symptom:**
```
Error: The host does not have the Runner. The following Runners are available
```

**Root Causes:**
1. Runner process crashed
2. Runner host out of disk/memory
3. Network connectivity issue
4. Runner configuration corrupted
5. Host in maintenance mode

**Quick Diagnosis:**
```bash
# Check runner status
ps aux | grep Runner.Listener | grep -v grep

# Check logs on runner host
tail -f /tmp/runner.log
ssh runner-host "ps aux | grep Runner"

# Check disk/memory
ssh runner-host "df -h && free -h"

# Check network
ssh runner-host "ping github.com"

# Check runner list in GitHub
gh run list --repo kushin77/self-hosted-runner | grep "Self-hosted"

# Check recent failures
gh run list --repo kushin77/self-hosted-runner --status failure
```

**Solutions:**
| Solution | Steps | Time |
|----------|-------|------|
| **Restart runner** | `ssh runner-host 'sudo systemctl restart actions-runner'` | 2 min |
| **Clear disk** | `ssh runner-host 'sudo du -sh /tmp/* \| sort -rh \| head -5'` then cleanup | 5 min |
| **Clear memory** | Check for memory leaks with `free -h && ps aux | sort -k6 -rh` | 3 min |
| **Recreate runner** | Using: `scripts/provision-runner.sh` | 10 min |
| **Offline/Online** | Label host for maintenance in GitHub | 2 min |

**Auto-Healing:**
- `automation-health-validator.yml` (runs every 6h)
- `runner-self-heal.yml` (auto-triggered if unhealthy)
- `legacy-node-cleanup.yml` (removes dead runners)

---

### **ERR-SECRET-001: Secret Not Found**

**Symptom:**
```
Error: secret "SECRET_NAME" is not set
Workflow failed because required secrets are missing
```

**Root Causes:**
1. Secret not configured in GitHub
2. Wrong secret name in workflow
3. Secret deleted
4. Secret scoped to different environment

**Quick Diagnosis:**
```bash
# List all configured secrets
gh secret list --repo kushin77/self-hosted-runner

# Search for secret by pattern
bash scripts/audit-secrets.sh --search "PATTERN"

# Check if secret is in workflow
grep "secrets\.SECRET_NAME" .github/workflows/*.yml

# Validate required secrets
bash scripts/audit-secrets.sh --validate
```

**Solutions:**
| Solution | Steps | Time |
|----------|-------|------|
| **Set missing secret** | `gh secret set SECRET_NAME --repo kushin77/self-hosted-runner` | 1 min |
| **Use correct name** | Check: [SECRETS_INDEX.md](SECRETS_INDEX.md) | 2 min |
| **Restore deleted secret** | Recreate from backup/vault | 5 min |
| **Check scope** | Org vs Repo vs Environment secret | 1 min |

**Prevention:**
- Every PR must update [SECRETS_INDEX.md](SECRETS_INDEX.md)
- Run: `bash scripts/audit-secrets.sh --validate` before deploying
- Read: [SECRETS_SETUP_GUIDE.md](SECRETS_SETUP_GUIDE.md)

---

## Errors by System

### **Infrastructure / Terraform**

| Error Code | Error | Cause | Fix Time |
|-----------|-------|-------|----------|
| ERR-TF-001 | State lock timeout | Concurrent apply | 10 min |
| ERR-TF-002 | Module not found | Wrong module path | 2 min |
| ERR-TF-003 | Variable validation error | Invalid variable | 1 min |
| ERR-TF-004 | Resource already exists | Duplicate creation | 2 min |
| ERR-TF-005 | Permission denied on resource | IAM role missing permission | 5 min |
| ERR-AWS-001 | OIDC token exchange failed | No AWS_OIDC_ROLE_ARN | 1 min |
| ERR-AWS-002 | Resource quota exceeded | Hit AWS account limit | 30 min |
| ERR-AWS-003 | Spot interruption | Spot instance terminated | 2 min |

---

### **Runners / Self-Hosted**

| Error Code | Error | Cause | Fix Time |
|-----------|-------|-------|----------|
| ERR-RUNNER-001 | Runner offline | Process crashed | 2-10 min |
| ERR-RUNNER-002 | Disk full | /tmp or /var full | 5-15 min |
| ERR-RUNNER-003 | Memory exhausted | No free RAM | 5-30 min |
| ERR-RUNNER-004 | Network unreachable | Connection dropped | 2-5 min |
| ERR-RUNNER-005 | Docker daemon not responding | docker.service down | 2 min |
| ERR-RUNNER-006 | SSH key auth failed | deploy_key invalid | 5 min |

---

### **Cloud / GCP / AWS**

| Error Code | Error | Cause | Fix Time |
|-----------|-------|-------|----------|
| ERR-GCP-001 | Workload ID token failed | WIP not configured | 8 min |
| ERR-GCP-002 | Secret Manager access denied | IAM role missing | 5 min |
| ERR-GCP-003 | Service account deleted | Account removed | 10 min |
| ERR-AWS-001 | OIDC token exchange failed | Role not trusted | 5 min |
| ERR-AWS-002 | S3 bucket not found | Bucket missing/deleted | 5 min |
| ERR-AWS-003 | ECR login failed | Registry auth failed | 5 min |

---

### **Secrets Management**

| Error Code | Error | Cause | Fix Time |
|-----------|-------|-------|----------|
| ERR-SEC-001 | Secret not found | Not configured | 1 min |
| ERR-SEC-002 | Rotation failed | Old creds still active | 10 min |
| ERR-SEC-003 | Invalid secret format | Wrong type/encoding | 5 min |
| ERR-SEC-004 | Permission denied on secret | IAM missing access | 3 min |
| ERR-SEC-005 | Secret leaked | Found in logs/code | CRITICAL |

---

### **Delivery / Deployment**

| Error Code | Error | Cause | Fix Time |
|-----------|-------|-------|----------|
| ERR-DEPLOY-001 | Image pull failed | Registry auth failed | 5 min |
| ERR-DEPLOY-002 | Health check timeout | App not healthy | 5-15 min |
| ERR-DEPLOY-003 | DNS not resolving | Route53 misconfigured | 5 min |
| ERR-DEPLOY-004 | Pod not scheduling | Resource constraints | 10-30 min |
| ERR-DEPLOY-005 | Rollback failed | Couldn't revert version | 10 min |

---

## Errors by Symptom

### **"Permission Denied" Error**

**Possible Causes:**
1. IAM role lacks permission
2. Secret empty/invalid
3. SSH key not authorized
4. Service account disabled

**Check Sequence:**
```bash
# 1. Verify secret exists and is not empty
bash scripts/audit-secrets.sh --validate

# 2. Check AWS/GCP permissions
aws iam get-role --role-name github-actions-terraform
gcloud iam service-accounts describe github-actions-terraform@gcp-eiq.iam.gserviceaccount.com

# 3. Check SSH key authorization
ssh-keygen -y -f /var/lib/runner/.ssh/deploy_key  # On runner host

# 4. Check service account status
gcloud iam service-accounts describe EMAIL --project=gcp-eiq
```

**Fix Priority:**
1. ✅ Check [SECRETS_INDEX.md](SECRETS_INDEX.md) for required secrets
2. ✅ Run: `bash scripts/audit-secrets.sh --validate`
3. ✅ Review IAM role/policy
4. ✅ Add missing permission
5. ✅ Restart workflow

---

### **"Timeout" Error**

**Possible Causes:**
1. Process taking too long (job timeout)
2. Network connection stuck
3. Resource waiting indefinitely
4. Deadlock between processes

**Check Sequence:**
```bash
# 1. Check timeout setting
grep "timeout-minutes:" .github/workflows/workflow.yml

# 2. Check process status
ps aux | grep -E "grep|terraform|docker" | grep -v grep

# 3. Check network
netstat -tuln | grep ESTABLISHED

# 4. Check logs for stuck point
tail -100 /tmp/runner.log | grep -E "ERROR|waiting|timeout"

# 5. Check system resources
top -b -n 1 | head -20
```

**Solutions:**
| Symptom | Action | Time |
|---------|--------|------|
| Job exceeds 360 min | Increase `timeout-minutes` or split job | 2 min |
| Process stuck | Cancel with `gh run cancel ID` | 2 min |
| Network hung | Restart runner | 2 min |
| Deadlock | Increase available resources or optimize code | 10 min |

---

### **"Out of Memory" Error**

**Possible Causes:**
1. Memory leak in application
2. Too many containers/processes
3. Cache file too large
4. Insufficient runner memory

**Check Sequence:**
```bash
# On runner host
free -h                              # Check total/available memory
ps aux | sort -k6 -rh                # Show processes by memory
du -sh /tmp/*                        # Check temp files
docker ps --format "table {{.ID}}\t{{.MemoryUsage}}"  # Docker memory

# During workflow
echo "Available memory: $(free -h | grep Mem)"
```

**Solutions:**
| Solution | Action | Time |
|----------|--------|------|
| Clean /tmp | `rm -rf /tmp/*` (during workflow) | 2 min |
| Reduce cache size | Limit `/tmp/cache` size | 5 min |
| Increase runner memory | Scale up runner instance | 10 min |
| Optimize code | Profile and reduce memory usage | 30 min |

---

### **"Connection Refused" Error**

**Possible Causes:**
1. Service not running
2. Port not exposed
3. Firewall blocking
4. Wrong port number

**Check Sequence:**
```bash
# Check service status
systemctl status redis-server  # or your service

# Check port listening
netstat -tulnp | grep LISTEN | grep PORT

# Check firewall
sudo iptables -L -n | grep PORT
aws ec2 describe-security-groups  # AWS security groups

# Test connectivity
nc -zv HOST PORT
telnet HOST PORT
```

**Solutions:**
| Service | Check | Fix |
|---------|-------|-----|
| Redis | `redis-cli ping` | `systemctl start redis-server` |
| Docker | `docker ps` | `systemctl start docker` |
| Vault | `vault status` | `vault operator unseal` |
| MinIO | `curl http://localhost:9000` | Check listener address |

---

## Error Code Reference

### **Format: ERR-SYSTEM-NNN**

- `SYSTEM` = AWS, GCP, TF (Terraform), RUNNER, SEC (Security), DEPLOY, etc.
- `NNN` = 001-999 sequential

### **Complete Error Code List**

**AWS Errors (ERR-AWS)**
- 001: OIDC token exchange failed
- 002: Resource quota exceeded
- 003: Spot interruption
- 004: S3 bucket not found
- 005: ECR login failed
- 006: IAM role missing permission
- 007: STS assume role failed
- 008: EC2 instance limit reached

**GCP Errors (ERR-GCP)**
- 001: Workload ID token exchange failed
- 002: Secret Manager access denied
- 003: Service account deleted/disabled
- 004: Project quota exceeded
- 005: Compute engine quota exceeded

**Terraform Errors (ERR-TF)**
- 001: State lock timeout
- 002: Module not found
- 003: Variable validation error
- 004: Resource already exists
- 005: Permission denied on resource
- 006: Backend initialization failed
- 007: Invalid HCL syntax
- 008: Version constraint conflict

**Runner Errors (ERR-RUNNER)**
- 001: Runner offline
- 002: Disk full
- 003: Memory exhausted
- 004: Network unreachable
- 005: Docker daemon not responding
- 006: SSH key auth failed
- 007: Actions runner service crash
- 008: Workflow job timeout

**Security Errors (ERR-SEC)**
- 001: Secret not found
- 002: Rotation failed
- 003: Invalid secret format
- 004: Permission denied on secret
- 005: Secret leaked/exposed
- 006: Signature verification failed
- 007: Certificate expired

**Deployment Errors (ERR-DEPLOY)**
- 001: Image pull failed
- 002: Health check timeout
- 003: DNS not resolving
- 004: Pod not scheduling
- 005: Rollback failed
- 006: Service mesh configuration error

---

## Debugging Tools

### **Discovery/Audit Tools**

```bash
# Find all secrets (and which are missing)
bash scripts/audit-secrets.sh --full
bash scripts/audit-secrets.sh --validate

# Find all workflows (and their purposes)
bash scripts/audit-workflows.sh --full
bash scripts/audit-workflows.sh --search "terraform"

# Find all scripts (and their functions)
bash scripts/audit-scripts.sh --full
bash scripts/audit-scripts.sh --critical

# Search for error in logs
grep -r "ERROR\|FAILED\|Exception" .github/workflows/
```

### **On Runner Host**

```bash
# Check runner process
ps aux | grep Runner.Listener | grep -v grep

# Check logs
tail -f /tmp/runner.log
journalctl -u actions-runner -n 100

# Check resources
free -h       # Memory
df -h         # Disk
top -b -n 1   # CPU

# Check network
netstat -tuln
ss -tlnp
ping github.com

# Check Docker
docker ps -a
docker logs CONTAINER_ID
docker system df
```

### **GitHub CLI**

```bash
# List failed runs in last 24 hours
gh run list --repo kushin77/self-hosted-runner --status failure --limit 10

# Get details of failed run
gh run view RUN_ID --repo kushin77/self-hosted-runner

# Check specific workflow
gh run list --repo kushin77/self-hosted-runner -w workflow.yml

# Trigger troubleshooting workflow
gh workflow run issue-tracker-automation.yml --repo kushin77/self-hosted-runner
```

### **AWS CLI**

```bash
# Check OIDC provider
aws iam list-open-id-connect-providers

# Check role trust policy
aws iam get-role-policy \
  --role-name github-actions-terraform \
  --policy-name trust-policy

# Check STS credentials
aws sts get-caller-identity
```

### **GCP CLI**

```bash
# Check workload identity pool
gcloud iam workload-identity-pools describe github-actions \
  --location=global --project=gcp-eiq

# Check service account
gcloud iam service-accounts describe \
  github-actions-terraform@gcp-eiq.iam.gserviceaccount.com \
  --project=gcp-eiq

# Test OIDC token
gcloud auth application-default print-access-token
```

---

## Prevention & Best Practices

### **Prevent Errors Before They Happen**

```bash
# Before every commit
bash scripts/audit-secrets.sh --validate    # Check secrets
bash scripts/audit-workflows.sh --lint      # Check workflows
bash scripts/test-e2e.sh --quick            # Quick tests

# Before every deployment
terraform plan -out=tfplan
terraform show tfplan                        # Review changes
aws cloudformation validate-template --template-body file://template.json

# Regular monitoring
automation-health-validator.yml              # Every 6 hours
terraform-phase2-drift-detection.yml         # Every 24 hours
runner-self-heal.yml                        # Every 30 minutes
```

### **Setup Alerts**

Create issues/alerts when:
- Runner offline > 30 minutes → Auto: `runner-self-heal.yml`
- Terraform apply fails → Auto: `issue-tracker-automation.yml`
- Secrets missing → Auto: `auto-resolve-missing-secrets.yml`
- Infrastructure drift detected → Auto notification to ops

---

## Getting Help

1. **Quick lookup**: Search this page for error code or symptom
2. **Detailed help**: Run `bash scripts/audit-*.sh --help`
3. **Check logs**: Review [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
4. **Ask Copilot**: Search [WORKFLOWS_INDEX.md](WORKFLOWS_INDEX.md), [SCRIPTS_REGISTRY.md](SCRIPTS_REGISTRY.md)
5. **Open issue**: Tag with `debugging` label for team support

---

*Last Updated: March 7, 2026*  
*Maintained by: DevOps & Support Team*  
*Next Review: June 7, 2026*
