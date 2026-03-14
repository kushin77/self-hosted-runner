# PHASE 2 WEEK 1 RUNBOOK: Setup & Testing (Dry-Run Mode)

## Timeline: March 14-21, 2026

### Monday, March 14: Initial Setup
- [x] Configure 7 remediation handlers
- [x] Set up dry-run monitoring
- [x] Create systemd service unit
- [ ] Run baseline health checks
- [ ] Validate handler triggers

**Expected:** Discovery of any environmental issues

### Tuesday-Wednesday, March 15-16: Handler Testing
- [ ] Test Handler 1: Node Not Ready (dry-run)
- [ ] Test Handler 2: DNS Failed (dry-run)
- [ ] Test Handler 3: API Latency (dry-run)
- [ ] Test Handler 4: Memory Pressure (dry-run)
- [ ] Test Handler 5: Network Issues (dry-run)
- [ ] Test Handler 6: Pod Crash Loop (dry-run)
- [ ] Verify Handler 7: Continuous Monitoring

**Expected:** <5% false positive rate

### Thursday-Friday, March 17-18: Threshold Tuning
- [ ] Review dry-run logs
- [ ] Calculate actual detection latency
- [ ] Tune detection thresholds
- [ ] Verify accuracy >80%
- [ ] Document learning

**Expected:** Refined parameters for Week 2

### Weekend, March 19-20: Monitoring Review
- [ ] Aggregate metrics from full week
- [ ] Identify any issues or patterns
- [ ] Update handler configurations if needed
- [ ] Prepare for Phase 2 Week 2 (gradual rollout)

**Expected:** Ready for active remediation mode

### Success Criteria (End of Week 1)
- ✅ All handlers tested successfully
- ✅ False positive rate <10%
- ✅ Detection latency <2 minutes
- ✅ No production impact (dry-run only)
- ✅ Team comfortable with procedures

### Go/No-Go Decision: March 21
- [ ] All dry-run tests passed
- [ ] Metrics collected and analyzed
- [ ] Team sign-off received
- [ ] **GO:** Proceed to Week 2 (active remediation)

### Immediate Actions
1. Enable auto-remediation-controller systemd service
2. Set DRY_RUN=false in handlers
3. Monitor closely first 24 hours
4. Be ready to rollback

---

**Phase 2 Week 1 Status**: 🟡 IN PROGRESS (Started March 14)  
**Next Phase**: Week 2 Gradual Rollout (March 17-24)
