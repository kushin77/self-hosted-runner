# DAY 3: KUBERNETES CRONJOB DEPLOYMENT — EXECUTION CHECKLIST
**Date**: March 12, 2026  
**Duration**: 20 minutes  
**Owner**: Platform Operator  
**Prerequisites**: Day 1 AND Day 2 MUST BE COMPLETE  
**Status**: ✅ Ready for Execution

---

## PRE-EXECUTION CHECKLIST (5 minutes)

Before starting Day 3:

- [ ] Day 1 PostgreSQL deployment verified ✅
- [ ] Day 2 Kafka & Protobuf deployment verified ✅
- [ ] You have read [DAY1_POSTGRESQL_EXECUTION_PLAN.md](DAY1_POSTGRESQL_EXECUTION_PLAN.md)
- [ ] You have read [DAY2_KAFKA_PROTOS_CHECKLIST.md](DAY2_KAFKA_PROTOS_CHECKLIST.md)
- [ ] Kubernetes cluster is accessible: `kubectl cluster-info`
- [ ] kubectl is configured: `kubectl config current-context`
- [ ] Kubernetes namespace exists: `kubectl get ns | grep nexus`
- [ ] Docker is running: `docker ps` (for image verification)

---

## WHAT THIS DOES

**Scope**: Deploy Nexus Normalizer as Kubernetes CronJob

**Components**:
1. **CronJob**: Scheduled container execution
   - Schedule: Every 5 minutes (`*/5 * * * *`)
   - Image: `us-east1-docker.pkg.dev/nexus-engine/containers/normalizer:v1.0.1`
   - Resources: 256MB RAM, 100m CPU

2. **RBAC**: Role-Based Access Control
   - ServiceAccount: `nexus-normalizer`
   - ClusterRole: `normalizer-reader`
   - Permissions: read pods, list services, query logs

3. **Secrets**: Reference GSM credentials
   - AWS OIDC token injection
   - Vault client auth
   - S3 bucket access

**Success Indicator**: CronJob deployed, first job runs within 5 minutes, logs visible in Cloud Logging.

---

## STEP-BY-STEP EXECUTION

### Step 1: Verify Kubernetes Cluster (3 minutes)

```bash
# Check cluster connectivity
kubectl cluster-info

# Expected output: Kubernetes is running at https://...

# Check node status
kubectl get nodes

# Expected: At least 1 node ready

# Check if nexus namespace exists
kubectl get ns nexus

# If namespace doesn't exist, create it:
# kubectl create ns nexus
```

---

### Step 2: Deploy RBAC & CronJob (10 minutes)

```bash
cd /home/akushnir/self-hosted-runner

# Run the deployment script
bash scripts/deploy/apply_cronjob_and_test.sh 2>&1 | tee logs/day3-execution.log

# In another terminal, monitor logs
kubectl logs -n nexus -l app=normalizer --tail=100 -f
```

**What's Happening**:
1. Creates ServiceAccount `nexus-normalizer` in namespace `nexus`
2. Creates ClusterRole `normalizer-reader` with pod/service read permissions
3. Binds role to service account via ClusterRoleBinding
4. Deploys ConfigMap with Kafka broker URLs
5. Creates Secret reference to GSM credentials
6. Deploys CronJob manifest
7. Waits for first job execution (max 5 minutes)
8. Verifies job completed successfully

**Progress Milestones**:
```
✅ Checking Kubernetes connectivity...
✅ Namespace: nexus (exists)
✅ Creating ServiceAccount: nexus-normalizer
✅ Creating ClusterRole: normalizer-reader
✅ Creating ClusterRoleBinding: normalizer-reader-binding
✅ Creating ConfigMap: normalizer-config
✅ Creating Secret reference: normalizer-secrets
✅ Deploying CronJob: nexus-normalizer (schedule: */5 * * * *)
✅ Waiting for first job execution... (may take up to 5 minutes)
✅ Job completed: nexus-normalizer-<timestamp>
✅ Job status: Succeeded
✅ All verifications passed
```

---

### Step 3: Verify Success (5 minutes)

After the script completes, run verification checks:

```bash
# 1. Check CronJob is deployed
kubectl get cronjob -n nexus

# Expected:
#   NAME                SCHEDULE      SUSPEND   ACTIVE   LAST SCHEDULE   AGE
#   nexus-normalizer    */5 * * * *   False     0        <time>          1m

# 2. Check service account
kubectl get sa -n nexus

# Expected: nexus-normalizer listed

# 3. Check that the first job ran
kubectl get jobs -n nexus

# Expected: nexus-normalizer-<timestamp> showing Succeeded

# 4. View job pod logs
LATEST_JOB=$(kubectl get jobs -n nexus --sort-by=.status.startTime | tail -1 | awk '{print $1}')
kubectl logs -n nexus -l job-name=$LATEST_JOB --tail=50

# Expected: Processing output, no errors, shows records normalized

# 5. Check RBAC permissions are working
kubectl auth can-i get pods --as=system:serviceaccount:nexus:nexus-normalizer -n nexus

# Expected: yes

# 6. Check normalizer pod resources (if pod is still running)
kubectl get pods -n nexus | grep normalizer

# If a pod exists from the job:
kubectl describe pod -n nexus <pod-name> | grep -A 5 "Limits\|Requests"

# Should show: 256Mi RAM, 100m CPU
```

**All checks pass?** ✅ Day 3 is COMPLETE. Production deployment FINISHED.

---

## TROUBLESHOOTING

### Error: "Unable to connect to the Kubernetes API server"

**Cause**: kubeconfig not configured or cluster is down

**Fix**:
```bash
# Check kubeconfig setup
kubectl config view

# Verify cluster access
kubectl cluster-info

# If kubeconfig is missing, reconfigure:
gcloud container clusters get-credentials nexus-cluster \
  --region us-east1 --project nexus-engine
```

### Error: "namespace nexus not found"

**Cause**: Namespace doesn't exist in the cluster

**Fix**:
```bash
# Create namespace
kubectl create ns nexus

# Label it for monitoring
kubectl label ns nexus monitoring=true

# Verify creation
kubectl get ns nexus
```

### Error: "CronJob deployment failed: image not found"

**Cause**: Container image doesn't exist or is not accessible

**Fix**:
```bash
# Verify image exists in the registry
gcloud container images list --repository=us-east1-docker.pkg.dev/nexus-engine/containers

# Verify image pull policy
kubectl get cronjob -n nexus -o yaml | grep -A 2 "image:"

# If needed, update the image in the manifest:
# scripts/deploy/apply_cronjob_and_test.sh references the image as an env var
# Modify scripts/deploy/cronjob-manifest.yaml and re-deploy
```

### Error: "CronJob created but jobs are not running"

**Cause**: CronJob may be suspended or scheduler is not running

**Fix**:
```bash
# Check if CronJob is suspended
kubectl get cronjob -n nexus -o yaml | grep suspend

# If suspend=true, enable it:
kubectl patch cronjob nexus-normalizer -n nexus \
  -p '{"spec":{"suspend":false}}'

# Check that kube-scheduler is running on nodes
kubectl get pods -n kube-system | grep scheduler

# Force a manual job run for testing:
kubectl create job --from=cronjob/nexus-normalizer test-normalizer -n nexus
```

### Error: "Job pod crashes with exit code 1"

**Cause**: Runtime error in normalizer binary or missing configuration

**Fix**:
```bash
# Get the pod name from the failed job
LATEST_JOB=$(kubectl get jobs -n nexus --sort-by=.status.startTime | tail -1 | awk '{print $1}')
POD=$(kubectl get pods -n nexus -l job-name=$LATEST_JOB -o jsonpath='{.items[0].metadata.name}')

# Check pod logs in detail
kubectl logs -n nexus $POD --previous  # For previous run if pod was deleted

# Check pod events for more context
kubectl describe pod -n nexus $POD | grep -A 10 "Events:"

# Common fixes:
# - Verify Secret is created and has correct keys
# - Check Kafka broker is accessible from within the pod
# - Verify database connection string in ConfigMap
```

### Error: "RBAC permission denied: cannot get pods"

**Cause**: ServiceAccount or ClusterRole binding not created correctly

**Fix**:
```bash
# Check service account exists
kubectl get sa -n nexus

# Check role exists
kubectl get clusterrole | grep normalizer

# Check role binding exists
kubectl get clusterrolebinding | grep normalizer

# Verify binding is correct
kubectl get clusterrolebinding normalizer-reader-binding -o yaml | grep serviceAccount

# If missing, re-run the RBAC setup part:
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nexus-normalizer
  namespace: nexus
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: normalizer-reader
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list"]
EOF
```

### Error: "Timeout waiting for job to complete"

**Cause**: Job is running but taking longer than expected, or is stuck

**Fix**:
```bash
# Check if job is actually running
kubectl get jobs -n nexus -w  # Watch mode

# Check pod logs while running
LATEST_JOB=$(kubectl get jobs -n nexus --sort-by=.status.startTime | tail -1 | awk '{print $1}')
kubectl logs -n nexus -l job-name=$LATEST_JOB -f

# If stuck for > 10 minutes, delete and retry
kubectl delete job $LATEST_JOB -n nexus
kubectl create job --from=cronjob/nexus-normalizer retry-normalizer -n nexus
```

---

## WHAT'S NEXT

After verification succeeds:

1. **Checkpoint**: Day 3 Complete ✅
2. **Status**: Full Nexus Engine Deployment Complete ✅
3. **Handoff**: Sign-off document at [FINAL_EXECUTION_SIGN_OFF_20260312.md](FINAL_EXECUTION_SIGN_OFF_20260312.md)
4. **Handoff**: Go back to [OPERATOR_HANDOFF_INDEX_20260312.md](OPERATOR_HANDOFF_INDEX_20260312.md) for post-deployment steps

---

## REFERENCE INFORMATION

### CronJob Schedule Format

```
*/5 * * * *
│   │ │ │ │
│   │ │ │ └─ Day of week (0-6) (Sunday=0)
│   │ │ └─── Month (1-12)
│   │ └───── Day of month (1-31)
│   └─────── Hour (0-23)
└─────────── Minute (*/5 = every 5 minutes)
```

### Pod Resource Allocation

| Resource | Request | Limit | Notes |
|----------|---------|-------|-------|
| Memory | 128Mi | 256Mi | Normalizer processes metadata |
| CPU | 50m | 100m | Light compute workload |

### Normalizer Job Flow

```
1. CronJob triggers (every 5 minutes)
   ↓
2. Creates new Job pod
   ↓
3. Pod starts Normalizer binary with env vars
   ↓
4. Normalizer reads from nexus.discovery.raw (Kafka)
   ↓
5. Applies cleaning/enrichment rules (GSM config)
   ↓
6. Writes to nexus.discovery.normalized (Kafka)
   ↓
7. Log output to Cloud Logging
   ↓
8. Pod completes, logs retained for 30 days
```

### Kubernetes RBAC Model

| Resource | Role | Binding | ServiceAccount |
|----------|------|---------|---|
| pods, services | get, list | ClusterRoleBinding | nexus-normalizer |

---

## GOVERNANCE VERIFICATION

After Day 3 completes, verify:

- ✅ **Immutable**: CronJob manifest stored in Git (readOnly in etcd)
- ✅ **Ephemeral**: No credentials in pod spec (ref via Secret)
- ✅ **Idempotent**: Job logic uses transaction semantics
- ✅ **No-Ops**: Fully automated scheduling (0 manual triggers)
- ✅ **Hands-Off**: OIDC token injected; no password auth
- ✅ **Logged**: Job output in Cloud Logging, 30-day retention

---

## SUCCESS METRICS

After Day 3:

| Metric | Expected | How to Verify |
|--------|----------|---------------|
| CronJob Deployed | ✅ | `kubectl get cronjob -n nexus` |
| Jobs Running | Every 5 min | `kubectl get jobs -n nexus` |
| Job Success Rate | 100% | `kubectl get jobs -n nexus \| grep Succeeded` |
| Data Flow | raw → normalized | Check Kafka topics |
| RBAC Working | ✅ | `kubectl auth can-i get pods --as=...` |
| Logs Ingested | ✅ | Check Cloud Logging dashboard |

---

## FINAL DEPLOYMENT STATUS

**All 3 Phases Complete**:
- ✅ **Day 1**: PostgreSQL (8 migrations, RLS policies, 45 min)
- ✅ **Day 2**: Kafka & Protobuf (4 topics, language bindings, 30 min)
- ✅ **Day 3**: Kubernetes CronJob (5-min intervals, RBAC, 20 min)

**Total Execution Time**: ~95 minutes

**Next Steps**:
1. Sign off on [FINAL_EXECUTION_SIGN_OFF_20260312.md](FINAL_EXECUTION_SIGN_OFF_20260312.md)
2. Monitor deployment for 24 hours
3. Archive execution logs
4. Update runbooks with latest IPs/DNS names

---

**Time Estimate**: 20 minutes  
**Complexity**: High (Kubernetes + RBAC)  
**Risk**: MEDIUM (K8s API, image registry, network policies)  
**Success Rate**: 85%+ (assuming Day 1+2 passed and K8s is healthy)

---

**Ready?** Run the script and verify all checks. Total time: ~20 minutes.  
**All done?** Celebrate. Production Nexus Engine is now deployed and running. 🎉
