# Full Stack Deployment Checklist for 192.168.168.42

**Target**: `192.168.168.42:3919` (Portal UI) + Backend Services  
**Date**: March 5, 2026  
**Status**: Ready for Deployment  

---

## 🔍 Pre-Deployment Verification

### Target Host Requirements (192.168.168.42)

- [ ] **SSH Access**: Verify `ssh cloud@192.168.168.42` works (or adjust `--user` flag)
- [ ] **Linux OS**: Ubuntu 20.04+ or Debian 11+ (run `uname -a` to confirm)
- [ ] **Node.js 18+**: Run `node --version` and `npm --version`
- [ ] **Disk Space**: At least 500MB free (`df -h /opt`)
- [ ] **Network Ports Available**:
  - [ ] Port 3919 (Portal UI): `nc -zv 192.168.168.42 3919`
  - [ ] Port 9090 (Metrics): `nc -zv 192.168.168.42 9090`
  - [ ] Port 4000 (Managed-Auth): `nc -zv 192.168.168.42 4000`
- [ ] **Directory Permissions**: Can create `/opt/self-hosted-runner` (test: `ssh cloud@192.168.168.42 mkdir -p /opt/test && rm -rf /opt/test`)

### Local Prerequisites

- [ ] Repository cloned: `/home/akushnir/self-hosted-runner`
- [ ] Scripts are executable: 
  ```bash
  chmod +x scripts/automation/pmo/deploy-full-stack.sh
  chmod +x scripts/automation/pmo/start-full-stack.sh
  ```
- [ ] Node.js 18+ on local machine (for building portal)
- [ ] npm available locally

---

## 📋 Deployment Steps

### Step 1: Build All Components (Local)

**Command**:
```bash
cd /home/akushnir/self-hosted-runner
./scripts/automation/pmo/deploy-full-stack.sh --stage stage1
```

**Expected Output**:
```
[✓] Portal built: dist/
[✓] Service provisioner-worker ready
[✓] Service managed-auth ready
[✓] Service vault-shim ready
[✓] Stage 1 complete: all components built
```

**Checklist**:
- [ ] Portal `dist/` directory created
- [ ] No build errors
- [ ] Dependencies installed for all services
- [ ] Log file generated at `/tmp/full-stack-deployment-*.log`

### Step 2: Deploy to Remote Host (SSH)

**Command**:
```bash
./scripts/automation/pmo/deploy-full-stack.sh --stage stage2 --target 192.168.168.42 --user cloud
```

**Expected Output**:
```
[✓] SSH connectivity verified
[✓] Portal deployed
[✓] Service provisioner-worker copied
[✓] Service managed-auth copied
[✓] Service vault-shim copied
[✓] Stage 2 complete: all files deployed
```

**What Happens**:
- SSH copies portal `dist/` to `/opt/portal/` on remote
- Backend services copied to `/opt/backend/services/`
- Automation scripts copied for operational use

**Checklist**:
- [ ] SSH prompts for password (if no key-based auth configured)
- [ ] No connection timeouts
- [ ] ~100-200MB transferred successfully
- [ ] All services appear on remote

### Step 3: Configure Services

**Command**:
```bash
./scripts/automation/pmo/deploy-full-stack.sh --stage stage3
```

**Expected Output**:
```
[✓] Configuration created
[✓] Data directories prepared
[✓] Stage 3 complete: services configured
```

**Checklist**:
- [ ] `/opt/backend/.env` created with:
  - `ENABLE_METRICS=true`
  - `METRICS_PORT=9090`
  - `USE_TERRAFORM_CLI=1`
- [ ] `/opt/backend/data/` directory writable

### Step 4: Start Services

**Command**:
```bash
./scripts/automation/pmo/deploy-full-stack.sh --stage stage4
```

**Expected Output**:
```
[✓] Starting provisioner-worker...
[✓] Starting managed-auth...
[✓] Starting portal UI on port 3919...
[✓] Verifying remote processes...
```

**Checklist**:
- [ ] No "address already in use" errors
- [ ] All three services start without immediate exit
- [ ] `nohup` logs created in `/tmp/`

### Step 5: Validate Deployment

**Command**:
```bash
./scripts/automation/pmo/deploy-full-stack.sh --stage stage5
```

**Expected Output**:
```
[✓] Portal responding on http://192.168.168.42:3919
[✓] Metrics endpoint available on http://192.168.168.42:9090/metrics
[✓] Managed-auth responding on http://192.168.168.42:3000
[✓] Stage 5 complete: deployment validated
```

**Manual Verification** (from your desktop):
```bash
# Portal UI
curl -I http://192.168.168.42:3919
# Expected: HTTP/1.1 200 OK

# Metrics
curl http://192.168.168.42:9090/metrics | head
# Expected: HELP and TYPE lines for Prometheus metrics

# Managed-auth health
curl http://192.168.168.42:4000/health
# Expected: ok
```

**Checklist**:
- [ ] Portal returns HTTP 200
- [ ] Metrics endpoint accessible
- [ ] Managed-auth responds
- [ ] All process IDs appear in remote process list

### Step 6: All-in-One Deployment

**Command** (replaces steps 1-5):
```bash
./scripts/automation/pmo/deploy-full-stack.sh --target 192.168.168.42 --user cloud
```

This will execute all stages sequentially with proper logging and error handling.

---

## 🌐 Access Portal

Once deployment succeeds:

1. **View Portal**: Open browser to `http://192.168.168.42:3919`
   - Should see RunnerCloud Portal dashboard
   - Mock data populated (runners, jobs, metrics)

2. **Check Metrics**: Browse to `http://192.168.168.42:9090/metrics`
   - Raw Prometheus metrics format
   - Look for `provisioner_*` metrics

3. **Monitor Services**: 
   ```bash
   ssh cloud@192.168.168.42
   ps aux | grep "node\|http-server"
   tail -f /tmp/provisioner-worker.log
   tail -f /tmp/managed-auth.log
   tail -f /tmp/portal.log
   ```

---

## ⚠️ Troubleshooting

### Portal shows 404 / Not Found

**Cause**: `dist/` not built or copied  
**Solution**:
```bash
# Rebuild locally
npm run build --prefix ElevatedIQ-Mono-Repo/apps/portal

# Verify on remote
ssh cloud@192.168.168.42 ls -la /opt/portal/dist/index.html
```

### Metrics endpoint returns 404

**Cause**: Provisioner-worker crashed or not running  
**Solution**:
```bash
# Check process
ssh cloud@192.168.168.42 ps aux | grep provisioner-worker

# Check logs
ssh cloud@192.168.168.42 cat /tmp/provisioner-worker.log | tail -50

# Restart manually
ssh cloud@192.168.168.42 'cd /opt/backend/services/provisioner-worker && ENABLE_METRICS=true METRICS_PORT=9090 nohup node worker.js > /tmp/pw-manual.log 2>&1 &'
```

### SSH Permission Denied

**Cause**: Wrong user or SSH key not configured  
**Solution**:
```bash
# Test connectivity
ssh -v cloud@192.168.168.42 echo OK

# If password required, ensure it's available or use key-based auth
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
ssh-copy-id -i ~/.ssh/id_ed25519.pub cloud@192.168.168.42
```

### Port Already in Use

**Cause**: Services from previous deployment still running  
**Solution**:
```bash
ssh cloud@192.168.168.42 pkill -f "node\|http-server"
sleep 2
./scripts/automation/pmo/deploy-full-stack.sh --stage stage4
```

---

## ✅ Success Criteria

Deployment is successful when:

1. [ ] Portal accessible at `http://192.168.168.42:3919` (HTTP 200)
2. [ ] Metrics accessible at `http://192.168.168.42:9090/metrics` (HTTP 200)
3. [ ] Managed-auth responds to `http://192.168.168.42:4000/health` (HTTP 200)
4. [ ] All three process running continuously for 5+ minutes
5. [ ] No "Error" or "Fatal" messages in remote logs
6. [ ] Portal UI displays without JavaScript console errors

---

## 📝 Post-Deployment Tasks

Once deployment succeeds:

1. [ ] Document actual deployment time and any issues
2. [ ] Load test portal with multiple concurrent users
3. [ ] Verify provisioning jobs execute correctly
4. [ ] Check metrics increment during provisioning
5. [ ] Set up log rotation (`logrotate`) on remote
6. [ ] Configure monitoring/alerting for production
7. [ ] Update Phase P3 issue (#146) with Observability next steps
8. [ ] Close Issue #153 (Prerequisites) and #154 (In-Progress Tracking)

---

## 📞 Support

If deployment fails at any step:

1. Check deployment log: `/tmp/full-stack-deployment-*.log` (local)
2. Check remote logs: `ssh cloud@192.168.168.42 tail -f /tmp/*.log`
3. Review troubleshooting section above
4. Create issue on GitHub with error messages and deployment log

---

**Deployment Initiated**: _____________  
**Deployment Completed**: _____________  
**Deployed By**: _____________  
**Sign-Off**: _____________  
