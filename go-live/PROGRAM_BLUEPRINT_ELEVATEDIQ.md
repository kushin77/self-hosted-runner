# Go-Live Program Blueprint (FAANG-style)

## Program Objective
Deliver a clean rebuild path for elevatediq.ai with enterprise controls, one-input bootstrap, and auditable stage gates.

## Single Required Input
- Domain: elevatediq.ai

## SNC (Standard Naming Convention)
- org: elevatediq
- env: dev (current), prod (future)
- project: nexusshield
- region-primary: us-central1
- naming pattern: <org>-<project>-<env>-<component>

Examples:
- gke cluster: elevatediq-nexusshield-dev-gke
- artifact repo: elevatediq-nexusshield-dev-artifacts
- service account: elevatediq-nexusshield-dev-deployer
- dns zone: elevatediq-ai-zone

## Stage Gates
1. Gate 0: Governance
- Security baseline approved
- IAM least privilege approved
- SNC lint passes

2. Gate 1: Platform
- VPC + IAM + KMS provisioned
- Secrets backends connected
- Artifact registry configured

3. Gate 2: Workload
- Kubernetes cluster created
- Namespace + policies applied
- Workloads deployed and healthy

4. Gate 3: Reliability
- SLOs, alerts, dashboards active
- Backup and DR drills green
- Runbooks validated

5. Gate 4: Release Readiness
- Production checklist complete
- Rollback proven
- Change approval complete

## Non-Negotiables
- No rebuild executed during reset mode
- Secrets preserved and never exfiltrated
- Runtime infra remains at zero after reset
- Every action logged in checkpoint/audit files

## Deliverables for Rebuild Start
- scripts/reset/rebuild-from-domain.sh
- scaffold/00-governance/rebuild-input.yaml
- scaffold/platform/terraform-root/ (empty scaffold)
- scaffold/pipelines/release-flow.yaml
- go-live/CHECKLIST.md
