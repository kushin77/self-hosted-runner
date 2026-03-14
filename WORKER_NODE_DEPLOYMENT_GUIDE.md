# Worker Node Deployment Instructions

**Target:** dev-elevatediq (192.168.168.42) - On-Premises Worker Node  
**NOT:** dev-elevatediq-2 (192.168.168.31) - Developer Workstation

---

## 📋 Deployment Steps

### Step 1: Make the deployment script executable

```bash
cd /home/akushnir/self-hosted-runner
chmod +x deploy-worker-node.sh
```

### Step 2: Transfer to worker node (one of the options below)

**Option A: Direct SSH execution** (if SSH is already set up)
```bash
ssh akushnir@192.168.168.42 'bash -s' < deploy-worker-node.sh
```

**Option B: Copy script to worker node and run manually**
```bash
# Copy the script to worker node
scp deploy-worker-node.sh akushnir@192.168.168.42:/tmp/

# SSH into worker node
ssh akushnir@192.168.168.42

# On worker node, run:
cd /tmp
bash deploy-worker-node.sh
```

**Option C: Set up SSH keys first (if not already authorized)**

On the **developer machine** (dev-elevatediq-2):
```bash
# Display public key
cat ~/.ssh/id_ed25519.pub
```

Then on the **worker node** (dev-elevatediq), add the key:
```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Paste the public key from above:
echo "ssh-ed25519 AAA..." >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

Then use Option A to deploy.

---

## ✅ What Gets Deployed

The deployment script will:
1. Verify running on correct host (dev-elevatediq)
2. Create `/opt/automation/` directory structure
3. Clone the repository
4. Deploy all 8 components:
   - `/opt/automation/k8s-health-checks/` (3 scripts)
   - `/opt/automation/security/` (1 script)
   - `/opt/automation/multi-region/` (1 script)  
   - `/opt/automation/core/` (3 scripts)
5. Verify all scripts are executable and syntactically valid
6. Generate deployment audit log

---

## 📍 Verification

After deployment, on the worker node verify with:

```bash
# List all components
ls -lh /opt/automation/*/

# Verify each script
bash -n /opt/automation/*/*.sh

# Check total installed
find /opt/automation -type f -name "*.sh" | wc -l
# Should return: 8
```

---

## 🚀 Using the Components

```bash
# Test Kubernetes health
/opt/automation/k8s-health-checks/cluster-readiness.sh

# Detect stuck deployments
/opt/automation/k8s-health-checks/cluster-stuck-recovery.sh

# Validate multi-cloud secrets
/opt/automation/k8s-health-checks/validate-multicloud-secrets.sh

# Audit for test values
/opt/automation/security/audit-test-values.sh

# Check failover status
/opt/automation/multi-region/failover-automation.sh

# Load credentials
source /opt/automation/core/credential-manager.sh

# Run orchestrator
/opt/automation/core/orchestrator.sh --operation deploy

# Monitor deployment
/opt/automation/core/deployment-monitor.sh
```

---

## ⚠️ Important Notes

- **NEVER run on dev-elevatediq-2** (developer workstation at 192.168.168.31)
- **ALWAYS deploy to dev-elevatediq** (worker node at 192.168.168.42)
- Deployment requires `git`, `bash`, `curl`, `rsync` on worker node
- Minimum 100MB free disk space required
- SSH key must be authorized on worker node first

---

## 🔧 Troubleshooting

**SSH Connection Refused:**
- Ensure SSH public key is in `~/.ssh/authorized_keys` on worker node
- Check SSH service is running: `systemctl status ssh`

**Permission Denied:**
- Script creates `/opt/automation/` with correct permissions
- May need `sudo` initially to create `/opt/automation/`

**Disk Space Error:**
- Check available space: `df -h /opt`
- Need at least 100MB free space

---

## 📊 Deployment Completion

Once deployed, you'll have:
- ✅ 8 automation scripts installed  
- ✅ 4 organized directories
- ✅ Full audit logging  
- ✅ Production-ready automation

**Status: 🟢 100% READY**
