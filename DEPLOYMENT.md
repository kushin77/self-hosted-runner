(Updated) Add a smoke verification step using `cloudbuild.smoke.yaml`.

After Phase0 resources are applied and Cloud Build integration is configured, trigger the smoke build:

```bash
# Trigger the smoke build manually
gcloud builds submit --config=cloudbuild.smoke.yaml . --project=PROJECT_ID
```

Or create a Cloud Build trigger that points at `cloudbuild.smoke.yaml` for one-off verification runs.
