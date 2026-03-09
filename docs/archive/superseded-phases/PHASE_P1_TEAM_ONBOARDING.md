# 🚀 Phase P1 TEAM ONBOARDING GUIDE

**Date**: March 4, 2026  
**Status**: ✅ Ready for Team Kickoff  
**Phase**: P1 (6-week development cycle)  
**Team**: Platform Engineering + Security + Data Science

---

## 👋 Welcome to Phase P1!

This guide will help you understand the Phase P1 project, your role, and how to get started with development.

---

## 📋 QUICK START (First Day)

### 1. Clone the Repository
```bash
git clone git@github.com:kushin77/self-hosted-runner.git
cd self-hosted-runner
git checkout main
```

### 2. Read Key Documentation
**30 minutes**:
- [PHASE_P1_PLANNING.md](PHASE_P1_PLANNING.md) - Full 6-week roadmap (start here!)
- [PROJECT_COMPLETION_SUMMARY.md](PROJECT_COMPLETION_SUMMARY.md) - What Phase P0 delivered

**15 minutes**:
- Your assigned GitHub issue (see your component below)
- Component skeleton code

**15 minutes**:
- [APPROVED_DEPLOYMENT.md](APPROVED_DEPLOYMENT.md) - Approval checklist
- [GITHUB_ISSUES_TRACKER.md](GITHUB_ISSUES_TRACKER.md) - Issue details

### 3. Setup Development Environment
```bash
# Frontend: Just bash scripts, git, and standard Unix tools
bash --version  # Should be 4.0+
which git curl ssh jq

# Optional: For ML features (Failure Prediction team)
python3 --version
pip install scikit-learn pandas numpy

# Optional: For Vault features (Secrets team)
# Install Vault CLI from https://www.vaultproject.io/downloads
vault --version
```

### 4. Explore Component Skeleton
Each component has a skeleton implementation in `/scripts/automation/pmo/`:
```bash
# Graceful Cancellation team:
cat scripts/automation/pmo/job-cancellation-handler.sh

# Secrets Rotation team:
cat scripts/automation/pmo/vault-integration.sh

# Failure Prediction team:
cat scripts/automation/pmo/failure-predictor.sh
```

### 5. Attend Team Sync
- **When**: [Scheduled by PM]
- **Agenda**: Phase P1 overview, team assignments, blockers
- **Duration**: 1 hour

---

## 👥 TEAMS & COMPONENTS

### Team 1: Graceful Job Cancellation (3 weeks)
**Issue**: [#1 - Graceful Job Cancellation Implementation](https://github.com/kushin77/self-hosted-runner/issues/1)  
**Owner**: [TBD - Assign lead Developer]  
**Team**: 1-2 backend engineers  
**Starts**: Week 1  
**Deliverables**: Signal handler, process cleanup, checkpoints

**Key Files**:
- Skeleton: `scripts/automation/pmo/job-cancellation-handler.sh` (6.3 KB)
- Config: `scripts/automation/pmo/examples/.runner-config/job-cancellation.yaml`
- Planning: [PHASE_P1_PLANNING.md - Week 1-3](PHASE_P1_PLANNING.md#week-1-graceful-job-cancellation)

**Success Criteria**:
- Graceful termination rate: >95% within grace period
- Process cleanup: 100% success
- Checkpoint recovery: Zero data loss

---

### Team 2: Secrets Rotation Vault Integration (2-3 weeks)
**Issue**: [#2 - Secrets Rotation Vault Integration](https://github.com/kushin77/self-hosted-runner/issues/2)  
**Owner**: [TBD - Assign lead Engineer]  
**Team**: 1-2 security/platform engineers + DevOps  
**Starts**: Week 2  
**Deliverables**: Vault auth, rotation daemon, audit logging

**Key Files**:
- Skeleton: `scripts/automation/pmo/vault-integration.sh` (9.4 KB)
- Config: `scripts/automation/pmo/examples/.runner-config/vault-rotation.yaml`
- Planning: [PHASE_P1_PLANNING.md - Week 2-4](PHASE_P1_PLANNING.md#week-2-secrets-rotation)

**Success Criteria**:
- Secret rotation success: 100%
- TTL compliance: 100%
- Credential cache hit rate: >80%

**External Dependency**: HashiCorp Vault server (contact platform team)

---

### Team 3: ML-Based Failure Prediction (2-3 weeks)
**Issue**: [#3 - ML-Based Failure Prediction Service](https://github.com/kushin77/self-hosted-runner/issues/3)  
**Owner**: [TBD - Assign lead Data Scientist]  
**Team**: 1-2 ML engineers + platform engineer  
**Starts**: Week 5  
**Deliverables**: Feature extraction, anomaly scoring, alerts

**Key Files**:
- Skeleton: `scripts/automation/pmo/failure-predictor.sh` (8.7 KB)
- Config: `scripts/automation/pmo/examples/.runner-config/failure-detection.yaml`
- Planning: [PHASE_P1_PLANNING.md - Week 5-7](PHASE_P1_PLANNING.md#week-5-failure-prediction)

**Success Criteria**:
- Prediction accuracy: >90%
- False positive rate: <5%
- Detection latency: <2 seconds

**Dependencies**: OTEL traces from Phase P0 (already deployed)

---

### Team 4: Integration & Testing (QA + Platform)
**Issue**: [#4 - Integration Testing & Production Hardening](https://github.com/kushin77/self-hosted-runner/issues/4)  
**Owner**: [TBD - Assign QA/Platform lead]  
**Team**: 1-2 QA engineers + platform engineer  
**Starts**: Week 6  
**Deliverables**: Integration tests, load tests, security review

---

### Team 5: Deployment (DevOps + Platform)
**Issue**: [#5 - Production Deployment & Rollout](https://github.com/kushin77/self-hosted-runner/issues/5)  
**Owner**: [TBD - Assign DevOps lead]  
**Team**: 1-2 DevOps engineers + platform engineer  
**Starts**: Week 8  
**Deliverables**: Canary deployment, monitoring, rollback

---

## 📚 DOCUMENTATION INDEX

**Critical Reading** (read first):
1. [PHASE_P1_PLANNING.md](PHASE_P1_PLANNING.md) - Complete 6-week roadmap
2. Your component's GitHub issue (#1-5 above)
3. [PHASE_P0_QUICK_REFERENCE.md](PHASE_P0_QUICK_REFERENCE.md) - How Phase P0 works

**Reference Docs**:
- [PHASE_P0_IMPLEMENTATION.md](PHASE_P0_IMPLEMENTATION.md) - Phase P0 internals you'll integrate with
- [PROJECT_COMPLETION_SUMMARY.md](PROJECT_COMPLETION_SUMMARY.md) - Complete project context
- [APPROVED_DEPLOYMENT.md](APPROVED_DEPLOYMENT.md) - Deployment procedures

**Configuration Templates**:
- `scripts/automation/pmo/examples/.runner-config/job-cancellation.yaml`
- `scripts/automation/pmo/examples/.runner-config/vault-rotation.yaml`
- `scripts/automation/pmo/examples/.runner-config/failure-detection.yaml`

---

## 🔧 DEVELOPMENT WORKFLOW

### Step 1: Create Feature Branch
```bash
git checkout -b feature/p1-job-cancellation
# or: feature/p1-vault-integration
# or: feature/p1-failure-prediction
```

### Step 2: Work on Your Component
- Build incrementally (don't wait to complete everything)
- Test locally often
- Push commits to your branch with clear messages

### Step 3: Test Your Code
```bash
# For shell scripts:
shellcheck scripts/automation/pmo/job-cancellation-handler.sh

# For Python (ML team):
pytest tests/test_failure_predictor.py -v

# Manual testing:
./scripts/automation/pmo/job-cancellation-handler.sh --help
./scripts/automation/pmo/job-cancellation-handler.sh --test
```

### Step 4: Create Draft Issue
```bash
git push origin feature/p1-job-cancellation
# Then open PR on GitHub with clear description
```

### Step 5: Code Review & Merge
- Request review from team lead and 1 other engineer
- Address feedback
- Merge when approved (squash commits)

---

## 🗓️ WEEKLY SCHEDULE

### Weekly Standup (Mondays 10am)
- **Duration**: 30 minutes
- **Attendees**: All Phase P1 teams
- **Agenda**: Progress update, blockers, rate of progress

### Component Sync (2x per week)
- **Duration**: 30 minutes each
- **Attendees**: Your component team
- **Agenda**: Technical decisions, code design, blockers

### Phase P1 Integration Sync (Thursdays 3pm)
- **Duration**: 1 hour (Weeks 6-8)
- **Attendees**: All teams + QA + DevOps
- **Agenda**: Integration testing, cross-component issues

---

## 🎯 KEY MILESTONES

| Week | Milestone | Teams |
|------|-----------|-------|
| 1-3 | Graceful Cancellation (Team 1) | Foundation for other teams |
| 2-4 | Secrets Rotation (Team 2) | Security foundation |
| 5-7 | Failure Prediction (Team 3) | Intelligence layer |
| 6 | Integration Testing Begins (Team 4) | All components |
| 7 | Security Hardening (Team 4+5) | All components |
| 8 | Production Deployment (Team 5) | Go-live! |

---

## 💡 BEST PRACTICES

### Code Quality
- ✅ Run shellcheck on all bash scripts
- ✅ Test with at least 2 test cases
- ✅ Handle error cases explicitly
- ✅ No hardcoded secrets or credentials
- ✅ Add comments for complex logic
- ✅ Log operations for debugging

### Git Commits
- ✅ Clear, descriptive commit messages
- ✅ Reference issue numbers: "Fix #123"
- ✅ Atomic commits (one logical change)
- ✅ Meaningful branch names: `feature/p1-xyz`

### Testing
- ✅ Unit tests for individual functions
- ✅ Integration tests with Phase P0
- ✅ Manual testing in staging environment
- ✅ Load testing (for relevant components)
- ✅ Test edge cases and error conditions

### Documentation
- ✅ Inline code comments for "why", not "what"
- ✅ README for each component
- ✅ Configuration examples with real values
- ✅ Troubleshooting guide for common issues
- ✅ Architecture diagrams where helpful

### Communication
- ✅ Update GitHub issue with progress daily
- ✅ Comment on Draft issues within 24 hours
- ✅ Flag blockers early in Slack
- ✅ Document design decisions in issue
- ✅ Share knowledge with other teams

---

## 🚧 COMMON BLOCKERS & SOLUTIONS

### "I don't understand Phase P0"
→ Read [PHASE_P0_QUICK_REFERENCE.md](PHASE_P0_QUICK_REFERENCE.md)  
→ Ask Phase P0 team member in #platform-p0 Slack channel

### "I need to integrate with Phase P0"
→ See integration section in your GitHub issue  
→ Review Phase P0 component you're integrating with  
→ Contact Phase P0 team lead for guidance

### "I'm blocked on external dependency"
→ Document blocker in GitHub issue  
→ @mention component owner in issue  
→ Post in #platform-blockers Slack channel  
→ Escalate to platform PM if urgent

### "My tests are failing"
→ Check Phase P0 is running correctly  
→ Verify test environment configuration  
→ Review error logs carefully  
→ Ask team members for help on Slack

### "I don't know how to test this"
→ See testing section in your GitHub issue  
→ Review Phase P0 testing approach  
→ Ask QA team member (#qa channel)

---

## 📞 GETTING HELP

### For Questions:
1. **Check documentation first** - Most answers are there
2. **Ask team members** - Your component team knows most
3. **Post in Slack** - #phase-p1 channel for team-wide questions
4. **Schedule 1:1** - Your component owner can help

### For Blockers:
1. **Document in GitHub issue**
2. **Post in #platform-blockers**
3. **Mention component owner**
4. **Escalate to PM if time-critical**

### For Code Review:
1. **Create Draft issue with clear description**
2. **Request review from team lead + 1 peer**
3. **Respond to reviews within 24 hours**
4. **Ask clarification if review is unclear**

---

## 📊 SUCCESS INDICATORS

You're on track if:
- ✅ Attending daily standups
- ✅ Making consistent progress (commits/Draft issues)
- ✅ Tests passing on your component
- ✅ Communicating blockers early
- ✅ Reviewing peers' code
- ✅ Documentation being written alongside code
- ✅ No surprises at end of week

---

## 🔐 SECURITY REMINDERS

- 🔒 Never commit secrets or credentials
- 🔒 Use environment variables for sensitive config
- 🔒 Always use HTTPS for remote URLs
- 🔒 Review code for security issues before PR
- 🔒 Test with untrusted input
- 🔒 Log sensitive operations for audit trail
- 🔒 Ask security team if unsure

---

## 📈 PROGRESS TRACKING

**Your GitHub Issue is your source of truth:**
- Track progress in issue description
- Update status weekly (Mon/Fri)
- Comment on blockers when they arise
- Celebrate wins when milestones hit

**GitHub Project Board:**
- Issues automatically tracked
- Columns: Backlog → In Progress → Code Review → Testing → Done
- Move issues as you work

**Weekly Sync:**
- Share progress in standup
- Highlight blockers
- Discuss cross-team dependencies

---

## 🎉 YOU'RE READY!

If you've read this guide and your component's GitHub issue, you're ready to start Phase P1 development!

**Next Actions:**
1. ✅ Read [PHASE_P1_PLANNING.md](PHASE_P1_PLANNING.md)
2. ✅ Read your component's GitHub issue (#1-5)
3. ✅ Setup development environment
4. ✅ Create feature branch
5. ✅ Start development!

---

**Questions?** Post in #phase-p1 Slack channel or comment on GitHub issue.  
**Blockers?** Post in #platform-blockers immediately.  
**Good luck and welcome to Phase P1! 🚀**

---

**Last Updated**: March 4, 2026  
**Phase P1 Status**: ✅ Team Kickoff Ready  
**Components**: 3 skeletons ready for development  
**Duration**: 6 weeks (Week 1-8)

For more context, see [PROJECT_COMPLETION_SUMMARY.md](PROJECT_COMPLETION_SUMMARY.md).
