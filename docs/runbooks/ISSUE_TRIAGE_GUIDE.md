# GitHub Issues Triage & Organization Guide

**Last Updated:** March 8, 2026  
**Repository:** kushin77/self-hosted-runner  
**Total Open Issues:** 50+  
**Organization Status:** ✅ REORGANIZED

---

## 📋 Issue Analysis Summary

### Issue Breakdown by Category
- **Operational/Urgent:** 10 issues (Blocking CI/deployment)
- **Infrastructure Features:** 25+ issues (10X enhancements + Sovereignty)
- **Security:** 4 issues (Vulnerabilities + Compliance)
- **Testing/Integration:** 8 issues (E2E, smoke tests, load testing)
- **Planning/Epics:** 15+ issues (Roadmap tracking)

### Labels Applied
| Label | Purpose | Count |
|-------|---------|-------|
| `priority/urgent` | Issues blocking all work | 4 |
| `priority/high` | Critical path issues | 8 |
| `priority/medium` | Important but not blocking | 6+ |
| `priority/low` | Backlog/planning | 15+ |
| `action-required` | Needs human action | 4 |
| `epic` | Strategic initiatives | 15+ |
| `phase1`, `phase2`, etc. | Implementation phases | 25+ |

---

## 🚨 URGENT - Do First (Next 24-48 hours)

### **Quick Wins - 30 minutes max**
1. **[#1355](https://github.com/kushin77/self-hosted-runner/issues/1355)** - Admin: Enable repository auto-merge
   - **Labels:** `ops`, `admin`, `priority/urgent`, `action-required`
   - **Action:** GitHub Repo Settings → Options → Enable "Allow auto-merge"
   - **Impact:** Unblocks fully hands-off automation
   - **Time:** 5 minutes

2. **[#500](https://github.com/kushin77/self-hosted-runner/issues/500)** - Actions blocked: billing/payment failed
   - **Labels:** `ci`, `billing`, `priority/urgent`, `blocker`
   - **Action:** Check GitHub Billing → Payment method → Spending limit
   - **Impact:** Unblocks all CI/CD pipelines
   - **Time:** 10 minutes

### **Medium Effort - 2-4 hours**
3. **[#1349](https://github.com/kushin77/self-hosted-runner/issues/1349)** - Security: Dependabot findings (10 vulnerabilities)
   - **Labels:** `security`, `dependabot`, `priority/urgent`, `vulnerability`
   - **Action:** Triage 7 high-severity, open remediation PRs
   - **Critical:** 7 high-severity vulns need fixes
   - **Time:** 2-3 hours

4. **[#1309](https://github.com/kushin77/self-hosted-runner/issues/1309)** & **[#1346](https://github.com/kushin77/self-hosted-runner/issues/1346)** - AWS/GCP OIDC Provisioning
   - **Labels:** `ops`, `terraform`, `aws`, `priority/high`, `action-required`
   - **Action:** Execute phases from OPERATOR_EXECUTION_SUMMARY.md
   - **Blocks:** Terraform auto-apply and hands-off automation
   - **Time:** 25 minutes (3 phases)

---

## 🔥 HIGH PRIORITY - Next Sprint (48 hours - 1 week)

### **Investigation Track** (Parallel)
5. **[#1064](https://github.com/kushin77/self-hosted-runner/issues/1064)** - Weekly DR Test Failures
   - **Labels:** `investigation`, `incident`, `dr`, `priority/high`
   - **Status:** Run #130 queued - waiting for completion
   - **Next:** Monitor run, auto-close if passes, investigate if fails
   - **Time:** 1-2 hours

6. **[#503](https://github.com/kushin77/self-hosted-runner/issues/503)** - CI failures on main (triage required)
   - **Labels:** `ci`, `bug`, `priority/high`, `triage`
   - **Status:** Multiple workflows failing after Phase 2 merges
   - **Action:** Triage which workflows + identify root causes
   - **Time:** 2-3 hours

7. **[#498](https://github.com/kushin77/self-hosted-runner/issues/498)** - Queued workflows stuck
   - **Labels:** `ci`, `investigation`, `runners`, `priority/high`
   - **Related:** #499, #505
   - **Action:** Check runner labels, concurrency, workflow constraints
   - **Time:** 1 hour

### **Lock Files & Dependencies** (Quick Fix)
8. **[#505](https://github.com/kushin77/self-hosted-runner/issues/505)** - npm ci errors in services/pipeline-repair
   - **Labels:** `ci`, `npm`, `bug`, `priority/high`
   - **Fix:** Regenerate package-lock.json locally + commit
   - **Time:** 30 minutes

9. **[#583](https://github.com/kushin77/self-hosted-runner/issues/583)** - npm vulnerabilities in portal (6 high)
   - **Labels:** `security`, `npm`, `vulnerability`, `priority/high`
   - **Action:** Update @typescript-eslint/* + minimatch
   - **Time:** 1-2 hours

---

## 📊 INFRASTRUCTURE ROADMAP - Phase-Based Delivery

### **Phase 1: 10X Performance (Weeks 1-2)**
**Epic:** [#482](https://github.com/kushin77/self-hosted-runner/issues/482) - 10X Infrastructure Enhancements
- **Labels:** `epic`, `infrastructure`, `performance`, `phase1`
- **Sub-issues:** #484 (Ephemeral), #485 (Terraform), #486 (One-Click Deploy)
- **Delivery:** Achieve 30min → 3min deployments

| Issue | Task | Status |
|-------|------|--------|
| [#484](#) | Ephemeral Infrastructure | Ready |
| [#485](https://github.com/kushin77/self-hosted-runner/issues/485) | High-Speed Terraform | Ready |
| [#486](https://github.com/kushin77/self-hosted-runner/issues/486) | One-Click Deploy Workflow | Ready |
| [#487](https://github.com/kushin77/self-hosted-runner/issues/487) | Integration & Validation | Ready |

### **Phase 2: Data-Plane & Self-Hosted Stack (Weeks 3-6)**
**Epic:** [#548](https://github.com/kushin77/self-hosted-runner/issues/548) - Self-hosted Data-Plane & SaaS Control-Plane
- **Labels:** `epic`, `roadmap`, `architecture`, `phase2`
- **Sub-epics:** MinIO (#518), Harbor (#512), Secrets (#510), Observability (#509), AI Gateway (#508), etc.
- **Child Tasks:** 30+ specific implementation tasks

#### Key Infrastructure Tasks:
| Issue | Type | Priority | Estimate |
|-------|------|----------|----------|
| [#523](https://github.com/kushin77/self-hosted-runner/issues/523) | MinIO Helm/Terraform | High | 2d |
| [#527](https://github.com/kushin77/self-hosted-runner/issues/527) | Harbor Integration | High | 3d |
| [#543](https://github.com/kushin77/self-hosted-runner/issues/543) | Observability Stack | High | 2d |
| [#544](https://github.com/kushin77/self-hosted-runner/issues/544) | Vault Secrets | High | 2d |
| [#520](https://github.com/kushin77/self-hosted-runner/issues/520) | Control Plane UI | Medium | 3d |

### **Phase 3: Sovereignty Framework (Weeks 7+)**
**Epics:** [#552-#561](https://github.com/kushin77/self-hosted-runner/issues/552) - SOV-001 through SOV-014
- **Labels:** `epic`, `sovereignty`, `phase2-planning`
- **Focus:** Complete independence from SaaS platforms
- **Key Areas:**
  - In-house Git server (#559)
  - GitOps deployments (#558)
  - Secrets & Vault (#557)
  - Private registries (#556)
  - Observability (#560)
  - RBAC & Compliance (#561)
  - Portal SaaS features (#562)

---

## 📈 Recommended Delivery Strategy

### **Week 1: Unblock CI & Secure Platform**
- ✅ Enable auto-merge (#1355) - 5 min
- ✅ Fix billing issue (#500) - 10 min
- ✅ Provision AWS/GCP OIDC (#1309, #1346) - 25 min
- 🔄 Triage Dependabot (#1349) - 2 hours
- 🔄 Fix npm issues (#505, #583) - 2 hours
- **Total:** ~4.5 hours (parallel with investigations)

### **Week 2: Investigation & Bug Fixes**
- 🔄 Investigate CI failures (#503, #498, #499) - 4 hours
- 🔄 Monitor DR test run (#1064) - 1 hour
- 📝 Document findings - 1 hour
- **Parallel:** Start Phase 1 infrastructure work
- **Total:** 6 hours

### **Week 3-4: Phase 1 Infrastructure**
- Start [#482](https://github.com/kushin77/self-hosted-runner/issues/482) sub-tasks in parallel:
  - Ephemeral infrastructure setup
  - Terraform optimization (parallelism=30)
  - One-click deploy workflow
  - Integration testing
- **Team:** 2-3 engineers in parallel

### **Week 5+: Phase 2 Data-Plane Stack**
- Deploy key infrastructure pieces:
  - MinIO (#523)
  - Harbor registry (#527)
  - Observability stack (#543)
  - Vault secrets (#544)
- **Team:** Parallel tracks for 2-3 engineers

### **Week 8+: Sovereignty Framework**
- Implement SOV-001 through SOV-14 epics
- Target: Full independence from GitHub-hosted services
- **Team:** 1-2 engineers steady pace

---

## 🎯 Prioritization Rules

### **When to Mark `priority/urgent`**
- Blocking CI/CD pipelines ✓
- Security vulnerabilities (high/critical) ✓
- Admin action required ✓
- Production incident ✓

### **When to Mark `priority/high`**
- Critical path for upcoming phase ✓
- Investigation/triage required ✓
- Test failures affecting delivery ✓
- Dependency for other issues ✓

### **When to Mark `priority/medium`**
- Important but can be deferred ✓
- Nice-to-have improvements ✓
- Infrastructure enhancements ✓
- Follow-up work ✓

### **When to Mark `priority/low`**
- Backlog planning ✓
- Future roadmap ✓
- Nice-to-have features ✓
- Research/exploration ✓

---

## 📌 Label Conventions

### **Priority Labels**
- `priority/urgent` - Do immediately (blocks all work)
- `priority/high` - Next sprint (blocks some work)
- `priority/medium` - Current phase
- `priority/low` - Backlog

### **Category Labels**
- `epic` - Strategic initiative / parent issue
- `task` - Specific work item / child of epic
- `bug` - Defect to fix
- `investigation` - Need to understand problem first
- `security` - Security-related work
- `ops` - Operational/infrastructure work
- `ci` - CI/CD related
- `testing` - Testing/QA work
- `docs` - Documentation

### **Status Labels**
- `action-required` - Needs human action
- `blocker` - Blocking other work
- `triage` - Needs initial investigation
- `follow-up` - Post-completion work

### **Phase Labels**
- `phase1` - 10X Infrastructure (Weeks 1-2)
- `phase2` - Data-Plane Stack (Weeks 3-6)
- `phase2-planning` - Sovereignty planning (Weeks 7+)
- `phase3` - Production hardening
- `phase4` - Validation & deployment

---

## 🔗 Issue Relationships & Dependency Map

### **Blocking Chains**
```
#500 (Billing)
  ├─> #503 (CI failures)
  │   ├─> #498 (Queued workflows)
  │   │   └─> #499 (Lockfile validation)
  │   └─> #505 (npm ci errors)
  └─> #482 (10X Infrastructure) [Can proceed once #500 fixed]

#1309 + #1346 (OIDC Provisioning)
  └─> #482 (10X Infrastructure) [Waiting for completion]

#1349 (Dependabot)
  └─> #583 (Portal npm vulns)
  └─> Security baseline
```

### **Phase Dependencies**
```
Phase 1 (#482):
  ├─> Phase 2 (#548) [Depends on speed gains]
  │   ├─> Phase 3 (#552-561) [Sovereignty framework]
  │   ├─> MinIO (#523)
  │   ├─> Harbor (#527)
  │   └─> Observability (#543)
  └─> Monitoring automation (#476, #478)
```

---

## 📋 Daily/Weekly Checklist

### **Daily Standup** (5 min)
- [ ] Check `priority/urgent` issues - any blockers?
- [ ] Check `action-required` issues - any waiting?
- [ ] Review new issues - triage into priority buckets
- [ ] Monitor queued CI runs - investigate if > 30 min

### **Weekly Review** (30 min)
- [ ] Close completed issues + tag as `status/done`
- [ ] Move completed issues out of active phase
- [ ] Review investigation progress - move to fixes
- [ ] Plan next week's deliverables from priority buckets

### **Sprint Planning** (1 hour)
- [ ] Review all `action-required` issues
- [ ] Assign owners to high-priority work
- [ ] Break epics into 2-week sprints
- [ ] Identify blockers early
- [ ] Estimate capacity for each phase

---

## ✅ Quick Reference: What to Do Next

### **Right Now** (0-30 min)
1. Enable auto-merge: [#1355](https://github.com/kushin77/self-hosted-runner/issues/1355)
2. Check billing: [#500](https://github.com/kushin77/self-hosted-runner/issues/500)
3. Provision OIDC: [#1309](https://github.com/kushin77/self-hosted-runner/issues/1309) + [#1346](https://github.com/kushin77/self-hosted-runner/issues/1346)

### **Today** (1-4 hours)
4. Triage Dependabot findings: [#1349](https://github.com/kushin77/self-hosted-runner/issues/1349)
5. Fix npm issues: [#505](https://github.com/kushin77/self-hosted-runner/issues/505) + [#583](https://github.com/kushin77/self-hosted-runner/issues/583)

### **This Week** (4-20 hours)
6. Investigate CI failures: [#498](https://github.com/kushin77/self-hosted-runner/issues/498), [#499](https://github.com/kushin77/self-hosted-runner/issues/499), [#503](https://github.com/kushin77/self-hosted-runner/issues/503)
7. Monitor DR tests: [#1064](https://github.com/kushin77/self-hosted-runner/issues/1064)

### **Next Sprint** (Phase 1 Start)
8. Start infrastructure acceleration: [#482](https://github.com/kushin77/self-hosted-runner/issues/482)
9. Plan Phase 2 rollout: [#548](https://github.com/kushin77/self-hosted-runner/issues/548)

---

## 📞 Questions?

For triage decisions, consult:
- **Priority guidance:** Section "When to Mark [priority/X]"
- **Label guidance:** Section "Label Conventions"
- **Dependency map:** Section "Issue Relationships & Dependency Map"

**Last Updated:** March 8, 2026  
**Maintained by:** DevOps/Automation Team
