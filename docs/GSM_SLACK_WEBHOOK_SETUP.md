
# Create Slack webhook in Google Secret Manager (GSM) and grant access

This document explains how to store the Slack webhook in Google Secret Manager (GSM) and provide the CronJob with access to fetch it at runtime. The repository includes an init utility at `scripts/utilities/gsm_fetch_token.sh` which uses the `gcloud` CLI to read secrets.

High-level options
 - Preferred (secure): Use Workload Identity Federation or a short-lived token mechanism so the cluster does not hold long-lived GCP keys.
 - Quick-start (works immediately): Create a GCP service account, grant it `roles/secretmanager.secretAccessor` for the secret, create a service-account key, store that key as a Kubernetes secret, and mount it into the init container. This is described below.

Prereqs
 - `gcloud` installed where you run the commands
 - Kubernetes `kubectl` with cluster access

Example commands (replace placeholders):

```bash
PROJECT=your-gcp-project
SECRET_NAME=SLACK_WEBHOOK
GSA_NAME=milestone-organizer-gsa
GSA_EMAIL=${GSA_NAME}@${PROJECT}.iam.gserviceaccount.com
NAMESPACE=ops
K8S_SECRET_NAME=gcp-sa-key
```

1) Create the GSM secret (push webhook value from stdin):

```bash
echo -n "$SLACK_WEBHOOK" | gcloud secrets create "$SECRET_NAME" --data-file=- --project="$PROJECT" || \
  gcloud secrets versions add "$SECRET_NAME" --data-file=- --project="$PROJECT"
```

2) Create a GCP service account and grant it permission to access the secret:

```bash
gcloud iam service-accounts create "$GSA_NAME" --project="$PROJECT"
gcloud secrets add-iam-policy-binding "$SECRET_NAME" \
  --member="serviceAccount:${GSA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --project="$PROJECT"
```

3) Quick-start: create a service-account key and store it in Kubernetes (short-lived keys are better; rotate/delete when done):

```bash
gcloud iam service-accounts keys create sa-key.json --iam-account="$GSA_EMAIL" --project="$PROJECT"
kubectl create secret generic "$K8S_SECRET_NAME" -n "$NAMESPACE" --from-file=key.json=sa-key.json
rm sa-key.json
```

4) Update the CronJob manifest to mount the Kubernetes secret and set `GOOGLE_APPLICATION_CREDENTIALS` for the init container that calls `gsm_fetch_token.sh`.

Add the following `volumes` and `volumeMounts` entries (YAML snippet):

```yaml
      volumes:
        - name: workspace
          emptyDir: {}
        - name: gh-token
          emptyDir: {}
        - name: gcp-sa-key
          secret:
            secretName: gcp-sa-key

      # in the init container (volumeMounts)
      volumeMounts:
        - name: gcp-sa-key
          mountPath: /var/run/gcp
          readOnly: true

      # export GOOGLE_APPLICATION_CREDENTIALS in the init container
      env:
        - name: GOOGLE_APPLICATION_CREDENTIALS
          value: /var/run/gcp/key.json
```

5) The init container can now call the included utility, for example:

```sh
/workspace/repo/scripts/utilities/gsm_fetch_token.sh "${SECRET_NAME}" /var/run/secrets/slack_webhook "${PROJECT}"
```

6) After the secret is written to `/var/run/secrets/slack_webhook`, the main container can read it and export as `SLACK_WEBHOOK` or pass into the app.

Notes and security recommendations
 - Prefer Workload Identity Federation or short-lived credentials to avoid storing long-lived JSON keys in the cluster.
 - Grant the minimum `roles/secretmanager.secretAccessor` on the specific secret, not on the whole project.
 - Rotate/delete the service-account key after the cluster is configured and migrate to a more secure approach.

If you want, I can:
 - Create the Kubernetes secret for the GCP key if you upload the `sa-key.json` or allow me to create it via `gcloud` here.
 - Patch the `k8s/milestone-organizer-cronjob.yaml` manifest and apply it once cluster access is available.
