# Go-Live Tomorrow: Head-to-Toe Review

## Scope
This checklist enforces a deterministic redeploy process for the full stack with domain-standard naming, security controls, governance, and backup policy validation.

## 1. Reinforce Process
- [ ] Single entrypoint used: scripts/redeploy/redeploy-100x.sh
- [ ] Preflight checks pass for tools and permissions
- [ ] Failure aggregation report generated in reports/redeploy

## 2. Speed
- [ ] Script linting and validation run in parallel
- [ ] Cache paths and NAS mount checks pass
- [ ] Redis and DB health checks pass post-deploy

## 3. Consistency
- [ ] Domain variable set to elevatediq.ai
- [ ] Env files generated from templates where missing
- [ ] Shared folder structure enforced
- [ ] Repeated logic routed through scripts/lib and scripts/redeploy

## 4. Security
- [ ] No plaintext secrets committed
- [ ] Service account key usage is ephemeral only
- [ ] Deployment runs with least privilege service accounts

## 5. Overlap and Duplication
- [ ] Duplicate script basenames report reviewed
- [ ] Overlapping deployment paths consolidated or documented

## 6. Enforcement
- [ ] Naming policy check passes for service accounts and resources
- [ ] Domain policy check passes (elevatediq.ai)

## 7. Governance
- [ ] Epic and child issues created/updated for all enhancement tracks
- [ ] Gap analysis published under reports/redeploy

## 8. Service Accounts
- [ ] Expected service account scripts and mappings are present
- [ ] SSH key-only policy validated

## 9. Standard Naming
- [ ] Prefix standard is elevatediq-*
- [ ] Domain references align to elevatediq.ai

## 10. Optimization
- [ ] Docker compose config validates
- [ ] Build and deploy command list minimized and deterministic

## 11. Full Review
- [ ] Go-live report generated and signed off

## 12. Redeployment Best Practices
- [ ] Idempotent scripts only
- [ ] Rollback command path documented
- [ ] Post-deploy verification included

## 13. Git Flow
- [ ] Feature branch merged to main
- [ ] Changes pushed
- [ ] Feature branch deleted

## 14. Rebuild Standardization
- [ ] Clean rebuild from config/redeploy/redeploy.env
- [ ] No manual, one-off edits required

## 15. Deltas and Gap Analysis
- [ ] Delta report generated in reports/redeploy
- [ ] Top gaps have owners and due dates

## 16. Tracking Issues/Epics
- [ ] scripts/redeploy/create-enhancement-issues.sh executed

## 17. Daily Rebuild Plan
- [ ] Scheduled daily rebuild procedure drafted
- [ ] Auto-trigger path identified and tested

## 18. NAS/Cache/Monitoring/Redis/DB
- [ ] NAS health check pass
- [ ] Redis and DB smoke checks pass
- [ ] Monitoring validation pass

## 19. NAS Backup Policy
- [ ] Daily incremental backup verified
- [ ] Weekly full backup verified
- [ ] 30-day full retention verified
- [ ] Old weekly backups cleanup verified
