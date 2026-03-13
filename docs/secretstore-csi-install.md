Secrets Store CSI + provider-aws (EKS) — Quick install

Prereqs:
- kubectl configured to the target cluster
- Helm 3 installed
- If using IRSA: create IAM role and annotate ServiceAccount (see infra/iam/milestone-organizer-irsa-policy.json)

Install the Secrets Store CSI driver and the AWS provider on EKS:

```bash
# add charts
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update

# install CSI driver
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system --create-namespace

# install provider-aws (as a daemonset)
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deploy/providers/aws-provider-installer.yaml

# Verify pods
kubectl -n kube-system get pods -l app=secrets-store-csi-driver
kubectl -n kube-system get pods -l app=secrets-store-csi-driver-provider-aws
```

Usage notes:
- Apply `k8s/secretproviderclass-aws.yaml` into the `ops` namespace.
- Ensure `k8s/milestone-organizer-cronjob.yaml` ServiceAccount has the correct `eks.amazonaws.com/role-arn` (IRSA) annotation, and that the IRSA role has the policy from `infra/iam/milestone-organizer-irsa-policy.json`.
- The CSI provider will mount secret files under `/var/run/secrets` as configured in the CronJob.

If using Google Secret Manager or Vault instead, install the appropriate provider and adapt `SecretProviderClass.provider` and parameters accordingly.
