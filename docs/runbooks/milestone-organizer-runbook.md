# Milestone Organizer — Deployment & Runbook

Purpose: instructions to deploy the milestone-organizer CronJob, validate it, and verify archival of audit artifacts.

Prerequisites
- kubeconfig with cluster admin access (able to create ServiceAccount, CronJob in `ops` namespace)
- AWS CLI configured with profile `dev` (or equivalent creds) for S3/KMS operations
- `kubectl`, `aws`, `gh`, `jq` installed locally

Files in repo
- `k8s/milestone-organizer-cronjob.yaml` — ServiceAccount + CronJob (single manifest)
- `scripts/automation/run_milestone_organizer.sh` — wrapper that produces audit artifacts
- `infra/terraform/archive_s3_bucket` — Terraform module that created S3 bucket & KMS

Deploy (one-liner)
Run this on an admin host with `kubectl` configured:

```sh
kubectl apply -f k8s/milestone-organizer-cronjob.yaml
```

Trigger a one-off test run (create job from CronJob)

```sh
kubectl create job --from=cronjob/milestone-organizer milestone-organizer-test-$(date +%s) -n ops
kubectl get pods -n ops -l job-name=$(kubectl get jobs -n ops -o jsonpath='{.items[-1].metadata.name}') -o name
kubectl logs -n ops <pod-name> -f
```

Verify IRSA (pod assumes role)
- In the pod shell (if `aws` CLI available):

```sh
kubectl exec -n ops -it <pod-name> -- /bin/sh
aws sts get-caller-identity --profile default
```

If the pod returns the role ARN `arn:aws:iam::...:role/milestone-organizer-irsa`, IRSA is correctly configured.

Verify audit artifacts written locally in the pod
- The wrapper writes append-only JSONL into `artifacts/milestones-assignments/` inside the repo workspace. Tail or copy them out:

```sh
kubectl cp -n ops <pod-name>:/workspace/repo/artifacts/milestones-assignments ./artifacts-milestones
ls -la ./artifacts-milestones
```

Verify archival to S3 (if enabled)

```sh
aws --profile dev s3 ls s3://akushnir-milestones-20260312/milestones/ || true
aws --profile dev s3api get-object --bucket akushnir-milestones-20260312 --key milestones/assignments_$(date +%Y%m%d).jsonl ./downloaded.jsonl || true
```

Manual local runner test (without cluster)
- If you cannot deploy to cluster, run the wrapper locally (needs `GH_TOKEN`, AWS creds):

```sh
export GH_TOKEN="$(gh auth token)"        # or set from secret manager
export AWS_PROFILE=dev
./scripts/automation/run_milestone_organizer.sh --apply
# Check artifacts
ls -la artifacts/milestones-assignments/
```

Troubleshooting
- kubectl connect error: ensure kubeconfig context is correct and API server reachable.
- IRSA not working: ensure ServiceAccount annotation `eks.amazonaws.com/role-arn` matches IAM role ARN and OIDC provider is registered.
- S3 upload failing: verify IAM role/policy includes `s3:PutObject` and `kms:GenerateDataKey` for the KMS key.

Next steps for operator
- Apply manifest using admin kubeconfig
- Watch job run and share pod logs if failures occur
- Confirm artifacts in S3 and KMS encryption

Contact: ops team — provide kubeconfig or run commands above on admin host to complete deployment and integration tests.

---

## Automated Deployment Script

For a complete deploy-and-test workflow, use the provided operator script:

```bash
export KUBECONFIG=/path/to/kubeconfig
export AWS_PROFILE=dev
./deploy/milestone-organizer-deploy-and-test.sh
```

Or specify kubecontext:
```bash
./deploy/milestone-organizer-deploy-and-test.sh --kubecontext my-cluster-context --aws-profile dev
```

This script:
1. Validates kubectl API access
2. Applies manifests (creates ops namespace, ServiceAccount, CronJob)
3. Creates a one-off job immediately
4. Streams pod logs until completion
5. Verifies S3 archival in the configured bucket

---

## Kubeconfig Setup

Ensure kubeconfig is configured before running deployment:

```bash
# Check current kubeconfig
echo $KUBECONFIG
kubectl config current-context

# Or set kubeconfig explicitly
export KUBECONFIG=~/.kube/config
```

On first deployment, the script will create:
- Namespace: `ops`
- ServiceAccount: `milestone-organizer-sa` (with IRSA annotation)
- CronJob: `milestone-organizer` (daily 02:00 UTC)

