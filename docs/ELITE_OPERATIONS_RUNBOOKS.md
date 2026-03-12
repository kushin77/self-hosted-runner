# 📋 ELITE MSP OPERATIONS RUNBOOKS
# Emergency procedures and common scenarios for ops developers

---

## RUNBOOK #1: Pipeline Failure Investigation & Resolution

### Symptom: Pipeline job fails at security:sast stage

**Checklist:**
- [ ] Check pipeline logs for specific error message
- [ ] Verify SAST configuration in .gitlab-ci.elite.yml
- [ ] Check for pattern mismatches in code

**Resolution Steps:**

```bash
# 1. View pipeline logs
curl -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://gitlab.com/api/v4/projects/${PROJECT_ID}/pipelines/${PIPELINE_ID}/jobs" \
  | jq '.[].name, .[].web_url'

# 2. Check specific job logs
curl -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://gitlab.com/api/v4/projects/${PROJECT_ID}/jobs/${JOB_ID}/trace"

# 3. Run semgrep locally to debug
semgrep --config=p/owasp-top-ten --json --output=local-sast.json .

# 4. Review findings
cat local-sast.json | jq '.results[] | {path, line, message}'

# 5. Fix issues in code
# ... make changes ...

# 6. Commit and trigger manual pipeline
git commit -m "fix: resolve SAST findings"
git push origin feature-branch
# Then use GitLab UI to manually retry
```

**Escalation:** If SAST findings are false positives, add to .semgrep-ignore or update rules

---

## RUNBOOK #2: Runner Goes Offline

### Symptom: No available runners - jobs stuck in queue

**Quick Check:**

```bash
# 1. Verify runner status
sudo gitlab-runner verify

# 2. Check runner logs
sudo journalctl -u gitlab-runner -f

# 3. Check system resources
free -h
df -h
top -b -n1 | head -20

# 4. Verify Docker/connectivity
docker ps
ping gitlab.com
curl -I https://gitlab.com/api/v4/runners
```

**Resolution:**

```bash
# Option A: Restart runner
sudo systemctl restart gitlab-runner
sudo systemctl status gitlab-runner

# Option B: Clear stale jobs
sudo gitlab-runner verify --delete
sudo gitlab-runner list

# Option C: Cleanup disk space (if full)
docker system prune -a --force
rm -rf /runner/builds/*/
sudo systemctl restart gitlab-runner

# Option D: Re-register runner (if completely broken)
sudo gitlab-runner unregister --name "primary-shell-executor"
export REGISTRATION_TOKEN="<from GitLab>"
sudo gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.com/" \
  --registration-token "${REGISTRATION_TOKEN}" \
  --executor "shell" \
  --description "primary-shell-executor" \
  --tag-list "self-hosted,docker,primary"
```

**Verification:**

```bash
# Confirm status
sudo gitlab-runner list
sudo gitlab-runner verify

# Trigger test pipeline
# Manual trigger via GitLab UI to confirm jobs now run
```

---

## RUNBOOK #3: Deployment to Production Blocked by Compliance Gate

### Symptom: deploy:production job blocked - "COMPLIANCE GATE FAILED"

**Analysis:**

```bash
# 1. Check compliance gate output
curl -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://gitlab.com/api/v4/projects/${PROJECT_ID}/pipelines/${PIPELINE_ID}/jobs" \
  | jq '.[] | select(.name=="audit:compliance-gate") | .status, .web_url'

# 2. View detailed error
curl -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://gitlab.com/api/v4/projects/${PROJECT_ID}/jobs/${JOB_ID}/trace" \
  | tail -50

# 3. Review what failed
# Output will show which checks failed:
#   - sast_passed
#   - dependency_check_passed
#   - container_scan_passed
#   - iac_compliance_passed
#   - test_coverage_80_percent
#   - no_secrets_exposed
#   - artifact_signed
```

**Resolution by Failure Type:**

**Case 1: SAST failed**
```bash
cd .
semgrep --config=p/owasp-top-ten --config=p/cwe-top-25 .
# Fix identified issues, commit, retry
```

**Case 2: Coverage < 80%**
```bash
cd backend && npm run test:cov
cat coverage/coverage-summary.json | jq '.total.lines.pct'
# Add tests to reach 80%, commit, retry
```

**Case 3: Container vulnerabilities**
```bash
trivy image ${REGISTRY_IMAGE}:${CI_COMMIT_SHORT_SHA}
# Either upgrade vulnerable packages or request exception
```

**Case 4: Secrets detected**
```bash
detect-secrets scan --baseline .secrets.baseline
# Review findings, remove secrets, add to .gitignore
```

**Case 5: IaC compliance failed**
```bash
checkov -d terraform/ --soft-fail
# Review Terraform warnings and fix misconfigurations
```

---

## RUNBOOK #4: High Cost Spike - Budget Exceeded

### Symptom: Alert "TenantCostExceedsBudget" triggered

**Investigation:**

```bash
# 1. Get cost breakdown
gsutil cat "${TENANT_COST_BUCKET}/cost-report.json" | jq '.'

# 2. Identify expensive resources
kubectl top pods -n production --sort-by=memory

# 3. Check recent deployments
kubectl rollout history deployment/app -n production

# 4. Review pipeline execution
curl -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "https://gitlab.com/api/v4/projects/${PROJECT_ID}/pipelines?order_by=created_at&sort=desc&per_page=20"
```

**Quick Actions:**

```bash
# Action 1: Pause expensive jobs
kubectl scale deployment app-canary -n production --replicas=0

# Action 2: Reduce pipeline parallelism
# Edit .gitlab-ci.elite.yml: reduce matrix dimensions temporarily

# Action 3: Use spot instances
kubectl edit deployment app -n production
# Change nodeSelector to spot: "true"

# Action 4: Enable aggressive cost controls
kubectl set resources deployment app -n production \
  --limits=cpu=1,memory=1Gi \
  --requests=cpu=500m,memory=512Mi
```

**Long-term Optimization:**

```bash
# 1. Identify unused resources
kubectl get deployments -n production -o custom-columns=NAME:.metadata.name,REPLICAS:.spec.replicas,AGE:.metadata.creationTimestamp

# 2. Consolidate similar jobs
# - Combine multiple test jobs into single job
# - Increase cache hit ratio

# 3. Use cheaper instance types
# Edit deployment YAML to use cost-optimized nodes

# 4. Implement scheduling policies
kubectl apply -f - <<EOF
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: cost-optimized
value: 100
globalDefault: false
EOF
```

---

## RUNBOOK #5: Failed Blue-Green Deployment Rollback

### Symptom: New version (green) is failing - need immediate rollback

**Emergency Procedure (< 2 minutes):**

```bash
# 1. Verify current state
kubectl get deployment app-blue app-green -n production -o wide

# 2. Check service selector
kubectl get svc myapp -n production -o jsonpath='{.spec.selector}'

# 3. If green is failing, switch back to blue
kubectl patch service myapp -n production \
  -p '{"spec":{"selector":{"variant":"blue"}}}'

# 4. Verify traffic switched
curl -I https://api.myapp.com/health

# 5. Check error rate dropped
kubectl logs -n production deployment/app-blue | tail -20

# 6. Scale down failed green
kubectl scale deployment app-green -n production --replicas=0
```

**Investigation (after stabilization):**

```bash
# 1. Get green logs
kubectl logs -n production deployment/app-green --tail=100

# 2. Check resource limits
kubectl describe pod -n production -l variant=green | grep -A 5 "Limits"

# 3. Check health probe configuration
kubectl get deployment app-green -n production -o yaml | grep -A 10 "livenessProbe"

# 4. Review recent changes
git log --oneline -10 -- Dockerfile
git diff HEAD~1 HEAD -- Dockerfile

# 5. Fix and redeploy
# Make corrections to green deployment
kubectl set image deployment/app-green \
  app=${REGISTRY_IMAGE}:v1.3.1 \
  -n production

kubectl scale deployment app-green -n production --replicas=3
kubectl rollout status deployment/app-green -n production --timeout=5m
```

---

## RUNBOOK #6: Pod CrashLoop in Production

### Symptom: Pods in app deployment restart continuously

**Diagnosis:**

```bash
# 1. Check pod status
kubectl get pods -n production -l app=myapp
kubectl describe pod -n production <pod-name>

# 2. View logs
kubectl logs -n production <pod-name> --tail=100
kubectl logs -n production <pod-name> --previous  # Previous run

# 3. Check events
kubectl get events -n production --sort-by='.lastTimestamp'

# 4. Check resource pressure
kubectl top nodes
kubectl top pods -n production -l app=myapp
```

**Common Causes & Fixes:**

**Case 1: OOM (Out of Memory)**
```bash
# Symptom: "OOMKilled" in status
# Fix #1: Increase memory limits
kubectl set resources deployment app -n production \
  --limits=memory=4Gi

# Fix #2: Identify memory leak
kubectl logs -n production <pod-name> | grep -i "memory\|allocated"
# Then update application code
```

**Case 2: Readiness Probe Failing**
```bash
# Symptom: Pod restarts in seconds, startup completes
# Check readiness config
kubectl get deployment app -n production -o yaml | grep -A 10 "readinessProbe"

# Increase startup time
kubectl patch deployment app -n production -p '
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "app",
          "readinessProbe": {
            "initialDelaySeconds": 60
          }
        }]
      }
    }
  }
}'
```

**Case 3: Missing ConfigMap/Secret**
```bash
# Symptom: "Error creating mount point" or "secret not found"
# Check mounted volumes
kubectl get configmap -n production
kubectl get secret -n production

# Create missing resource
kubectl create configmap app-config \
  --from-file=config.yaml \
  -n production

# Or create secret
kubectl create secret generic db-secret \
  --from-literal=password=$(openssl rand -base64 32) \
  -n production
```

---

## RUNBOOK #7: Artifact Storage Quota Exceeded

### Symptom: "Artifact storage full" alert fired

**Cleanup Procedure:**

```bash
# 1. Check current usage
df -h /artifacts
du -sh /artifacts/* | sort -hr | head -20

# 2. Identify old artifacts
find /artifacts -type f -mtime +30 -exec ls -lh {} \;

# 3. Archive old artifacts
tar -czf /archive/artifacts-2026-03.tar.gz \
  $(find /artifacts -type f -mtime +30)

# 4. Delete archived artifacts
find /artifacts -type f -mtime +30 -delete

# 5. Cleanup Docker images
docker image prune -a --force

# 6. Cleanup runner cache
rm -rf /runner/cache/*

# 7. Run optimization
docker system df
docker system prune --volumes --force
```

**Prevention:**

```bash
# Edit .gitlab-ci.elite.yml to set artifact expiration
artifacts:
  expire_in: 7 days  # For dev branches
  # expires_in: 30 days  # For main branch
```

---

## RUNBOOK #8: Security Vulnerability Patch - Emergency Response

### Symptom: Critical CVE discovered (e.g., Log4j, OpenSSL)

**Immediate Actions (15 minutes):**

```bash
# 1. Assess impact
npm list ${VULNERABLE_PACKAGE}  # Node.js
pip list | grep ${VULNERABLE_PACKAGE}  # Python
grep -r "${VULNERABLE_PACKAGE}" . # All

# 2. Check if running in production
kubectl get deployment -n production -o yaml | grep "${VULNERABLE_PACKAGE}" || echo "Not found"

# 3. Upgrade package
npm update ${VULNERABLE_PACKAGE}
pip install --upgrade ${VULNERABLE_PACKAGE}

# 4. Rebuild container
docker build -t ${REGISTRY_IMAGE}:hotfix-${CVE_ID} .

# 5. Deploy to staging first
kubectl set image deployment/app-staging \
  app=${REGISTRY_IMAGE}:hotfix-${CVE_ID} \
  -n staging

# 6. Brief testing
curl -I https://staging.myapp.ops/health

# 7. Deploy to production (canary)
kubectl set image deployment/app-canary \
  app=${REGISTRY_IMAGE}:hotfix-${CVE_ID} \
  -n production

# Monitor canary for 5 minutes
watch 'kubectl logs -n production deployment/app-canary --tail=5'

# 8. Full production rollout
kubectl set image deployment/app \
  app=${REGISTRY_IMAGE}:hotfix-${CVE_ID} \
  -n production
```

**Documentation:**

```bash
# Create incident record
cat > INCIDENT_${CVE_ID}.md <<EOF
# Security Incident: ${CVE_ID}

## Timeline
- **Discovered:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Analyzed:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Patched:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
- **Deployed:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Impact
- Affected components: [list]
- Severity: CRITICAL
- Exploitable: Yes/No

## Resolution
- Package updated to version X.Y.Z
- Container rebuilt and deployed
- Monitoring: [link to dashboard]

## Verification
- Staging: ✓ Tested
- Canary: ✓ Monitoring (5 min)
- Production: ✓ Deployed
EOF

git add INCIDENT_${CVE_ID}.md
git commit -m "docs: incident record for ${CVE_ID}"
git push origin main
```

---

## QUICK REFERENCE TABLE

| Scenario | Runbook # | Resolution Time |
|----------|-----------|-----------------|
| Pipeline fails to run | #1 | 5-10 min |
| Runner offline | #2 | 2-5 min |
| Deployment blocked | #3 | 10-30 min |
| Cost spike | #4 | 15-30 min |
| Bad deployment | #5 | <2 min (emergency) |
| CrashLoop pod | #6 | 10-20 min |
| Storage full | #7 | 5-10 min |
| Security CVE | #8 | 15-30 min |

---

## Support Contacts

| Team | Slack | PagerDuty | Email |
|------|-------|-----------|-------|
| DevOps | #devops | sre-oncall | devops@company.com |
| Platform | #platform-eng | platform-oncall | platform@company.com |
| Security | #security | security-oncall | security@company.com |

---

**Last Updated:** March 12, 2026  
**Version:** 2.0 (Elite)  
**Maintained By:** SRE/DevOps Team
