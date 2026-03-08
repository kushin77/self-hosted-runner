# GCP Workload Identity Federation (WIF) Terraform Module

This directory contains Terraform scaffolding to create a Workload Identity Pool and Provider.

Usage notes:
- The workflow `deploy-cloud-credentials.yml` will attempt to run any Terraform here when run with `dry_run=false`.
- This module is idempotent: re-running terraform apply will converge to the same state.
- For first-run fully-automated execution you must provide a GCP admin credential as a repository secret (or run the workflow from an environment where `gcloud` is authenticated).

Example variables to configure in `terraform.tfvars`:
- project_id = "your-gcp-project"
- provider_name = "github-actions-wif"
