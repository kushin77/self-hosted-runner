# Phase P3 → P4: Production Rollout Quick Reference

One-page guide for Ops/Infra to unblock and execute the production rollout for Phase P3.

## TL;DR: What needs to happen

1. **Ops**: Add 2 secrets (Slack + PagerDuty webhooks)
2. **Ops**: Add 2 secrets (GCP creds + terraform vars)
3. **Infra**: Approve terraform plan
4. **Infra**: Execute terraform apply
5. **Ops**: Validate observability dashboards and alerts are live

**Estimated effort**: ~30 mins secrets setup + 1 hr plan review + 30 mins apply (during maintenance window)

---

## Step 1: Add Observability Secrets (Ops) — 5 mins

Navigate to: Settings → Secrets and Variables → Actions

Add these **Repository** secrets (or org-scoped):
- `SLACK_WEBHOOK_URL` = your Slack incoming webhook URL
- `PAGERDUTY_SERVICE_KEY` = your PagerDuty integration key

**Where to get these**:
- Slack: Incoming Webhooks app → Create New Webhook for #alerts channel
- PagerDuty: Services → select service → Integrations → copy service key OR create integration if needed

---

## Step 2: Test Observability with Real Receivers (Ops) — 10 mins

Once secrets are added:

1. Go to: Actions → Observability E2E → Run workflow
2. Set `test_real=true`
3. Wait for run to complete (2-3 mins)
4. Download artifact `observability-e2e-logs` and confirm Slack/PagerDuty received test alerts

If test passes → proceed. If fails, troubleshoot receiver URLs in secrets.

---

## Step 3: Add Terraform Secrets (Ops) — 5 mins

Navigate to: Settings → Secrets and Variables → Actions

Add these **Repository** secrets (or org-scoped):
- `PROD_TFVARS` = full content of your `terraform/prod.tfvars` file (populated from `terraform/prod.tfvars.example`)
- `GOOGLE_CREDENTIALS` = JSON service account key for GCP (save as file, copy its contents)

**Important**: Do NOT commit these files to the repo. Paste only into the secrets UI.

---

## Step 4: Run Terraform Plan (Infra) — 30 mins

Once secrets are added:

1. Go to: Actions → Terraform Plan/Apply → Run workflow
2. Leave `apply` = false (default)
3. Wait for run to complete (5-10 mins)
4. Download artifact `terraform-plan` and review changes locally:

```bash
terraform show -json terraform-plan/prod.tfplan | jq . > /tmp/plan.json
# or use terraform show directly:
terraform show terraform-plan/prod.tfplan
```

5. Review resources, costs, and confirm no destructive changes

---

## Step 5: Get Infra Sign-Off (Infra) — ongoing

Check issue #231 (Pre-apply verification sign-off):
- [ ] VPC/subnet/runner-token confirmed
- [ ] GCP permissions verified
- [ ] Vault unsealing secrets validated
- [ ] No resource conflicts with current infra
- [ ] Backup of terraform state completed

Once all checked, indicate approval in #231 or here.

---

## Step 6: Execute Terraform Apply (Infra) — 30 mins (during maintenance window)

Two options:

### Option A: GitHub Actions (Recommended for ease)
1. Go to: Actions → Terraform Plan/Apply → Run workflow
2. Set `apply` = true
3. Run workflow (will generate fresh plan and apply it)
4. Monitor for errors; all output is visible in the Actions log

### Option B: Local/Manual (if you prefer)
```bash
cd terraform
cp prod.tfvars.example prod.tfvars
# edit prod.tfvars with real values
terraform init -input=false
terraform plan -var-file=prod.tfvars -out=prod.tfplan -input=false
# review and then apply:
terraform apply -input=false prod.tfplan
```

---

## Step 7: Validate Production (Ops) — 20 mins

After terraform apply completes:

1. **Confirm observability stack is live**:
   ```bash
   curl http://<host>:9095  # Prometheus
   curl http://<host>:9096  # Alertmanager
   curl http://<host>:3000  # Grafana (if port mapped)
   ```

2. **Check Prometheus targets**:
   - Navigate to Prometheus UI → Status → Targets
   - Confirm all targets are "UP"

3. **Check Grafana dashboards**:
   - Log into Grafana (default: admin/admin if not customized)
   - Confirm dashboards are provisioned and metrics are flowing

4. **Run observability E2E one more time**:
   - Actions → Observability E2E → Run workflow with `test_real=true`
   - Confirm Slack/PagerDuty still receive test alerts

5. **Create a test incident and verify alerting**:
   - Manually trigger a test alert from Prometheus or create a test incident
   - Confirm alerts route to Slack/PagerDuty and match escalation policy

---

## Troubleshooting

**Terraform plan fails**: Missing vars in `prod.tfvars` or invalid GCP creds. Check error message and retry with complete secrets.

**Observability E2E fails**: Check `SLACK_WEBHOOK_URL` and `PAGERDUTY_SERVICE_KEY` are correct and URLs are accessible from the runner.

**Grafana not loading dashboards**: Check provisioning paths in docker-compose or terraform output; confirm Docker volumes are mounted.

**Prometheus not scraping**: Check `prometheus.yml` and alert rules; restart container if needed.

---

## Master Issue

Track all rollout tasks in: #240 (Phase P3 → Phase P4: Production Rollout Execution)

## Questions?

Reply in the relevant issue (#226, #227, #228, #231, #237, #240) or contact the delivery team.

---
**Generated**: 2026-03-05  
**Status**: Ready for Ops/Infra execution
