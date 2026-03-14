#!/bin/bash
#
# WORKER NODE DEPLOYMENT - README
# For: dev-elevatediq (192.168.168.42)
#
# This document describes the components being deployed
# and how to verify successful deployment
#

cat << 'EOF'

╔═════════════════════════════════════════════════════════════════════════════╗
║                  WORKER NODE DEPLOYMENT - DOCUMENTATION                    ║
║                      Target: dev-elevatediq (192.168.168.42)               ║
╚═════════════════════════════════════════════════════════════════════════════╝

═════════════════════════════════════════════════════════════════════════════
1. DEPLOYMENT OVERVIEW
═════════════════════════════════════════════════════════════════════════════

This deployment installs 8 critical automation components to the worker node:

Location: /opt/automation/

Structure:
├── k8s-health-checks/         # Kubernetes cluster health & recovery
│   ├── cluster-readiness.sh
│   ├── cluster-stuck-recovery.sh
│   └── validate-multicloud-secrets.sh
├── security/                  # Security audit & validation
│   └── audit-test-values.sh
├── multi-region/              # Failover & multi-cloud management
│   └── failover-automation.sh
├── core/                      # Core automation orchestration
│   ├── credential-manager.sh
│   ├── orchestrator.sh
│   └── deployment-monitor.sh
└── audit/                     # Deployment & execution logs

═════════════════════════════════════════════════════════════════════════════
2. COMPONENT DESCRIPTIONS
═════════════════════════════════════════════════════════════════════════════

K8s HEALTH CHECKS (4 Scripts)
────────────────────────────────

cluster-readiness.sh
  Purpose: Verify Kubernetes cluster is ready for deployments
  Functionality:
    • Check control plane node status
    • Validate API server connectivity
    • Verify etcd cluster health
    • Test DNS resolution
    • Verify all system pods running
  When to run: Before any deployment
  Expected output: Ready/Not Ready status

cluster-stuck-recovery.sh
  Purpose: Recover from stuck cluster states
  Functionality:
    • Detect and clear stuck workloads
    • Force evict problematic pods
    • Recover deleted nodes
    • Reset controller managers
    • Restore cluster state
  When to run: When cluster deployment hangs
  Expected output: Recovery actions and results

validate-multicloud-secrets.sh
  Purpose: Verify secrets across multi-cloud environments
  Functionality:
    • Check AWS Secrets Manager
    • Validate Azure Key Vault
    • Verify GCP Secret Manager
    • Test credential rotation
    • Validate encryption keys
  When to run: After secret updates
  Expected output: Secret validation report


SECURITY COMPONENTS (1 Script)
──────────────────────────────

audit-test-values.sh
  Purpose: Security audit and test value validation
  Functionality:
    • Audit all deployed secrets and configs
    • Validate test/dev values not in production
    • Check IAM policy compliance
    • Verify ABAC/RBAC configurations
    • Generate security report
  When to run: Daily or before production deployments
  Expected output: Pass/Fail security audit


MULTI-REGION FAILOVER (1 Script)
────────────────────────────────

failover-automation.sh
  Purpose: Manage failover between regions
  Functionality:
    • Monitor primary region health
    • Detect region outages
    • Migrate workloads to backup region
    • Update DNS/load balancer
    • Verify failover success
    • Auto-scale in backup region
  When to run: Automatically on failure detection
  Expected output: Failover completion status


CORE AUTOMATION (3 Scripts)
───────────────────────────

credential-manager.sh
  Purpose: Centralized credential & secret management
  Functionality:
    • Inject secrets from vaults into pods
    • Rotate credentials automatically
    • Update TLS certificates
    • Manage API keys and tokens
    • Audit all credential access
  When to run: Scheduled (hourly/daily rotation)
  Expected output: Credential update logs

orchestrator.sh
  Purpose: Master automation orchestration
  Functionality:
    • Coordinate all automation workflows
    • Execute scripts in correct order
    • Handle dependencies between tasks
    • Manage resource allocation
    • Enable parallel execution
  When to run: As master controller script
  Expected output: Workflow execution status

deployment-monitor.sh
  Purpose: Monitor ongoing deployments
  Functionality:
    • Track deployment progress
    • Monitor resource usage
    • Alert on failures
    • Collect deployment metrics
    • Generate deployment reports
  When to run: Continuously during deployments
  Expected output: Deployment status and metrics


═════════════════════════════════════════════════════════════════════════════
3. PRE-DEPLOYMENT CHECKLIST
═════════════════════════════════════════════════════════════════════════════

Before running deploy-standalone.sh, verify:

System Requirements:
□ OS: Linux (RHEL/CentOS/Ubuntu/Debian)
□ Kernel: 4.15+
□ Disk Space: 100 MB available in /opt
□ Memory: 1 GB minimum
□ CPU: 2 cores recommended

Required Commands:
□ bash        - Shell interpreter
□ git         - Repository cloning
□ curl        - Network requests
□ rsync       - File synchronization
□ tar/gzip    - Archive handling
□ grep, sed   - Text processing

Network Access:
□ GitHub.com reachable (for cloning)
□ Kubernetes API server connectivity
□ AWS/Azure/GCP credential access

Permissions:
□ User has sudo access (for /opt/automation)
□ Permission to create directories
□ Permission to execute scripts

Device:
□ Correct hostname: dev-elevatediq
□ Correct IP: 192.168.168.42
□ Network connectivity verified


═════════════════════════════════════════════════════════════════════════════
4. DEPLOYMENT STEPS
═════════════════════════════════════════════════════════════════════════════

Step 1: Prepare Deployment Environment
────────────────────────────────────────

# Verify prerequisites
hostname          # Should be: dev-elevatediq
hostname -I       # Should contain: 192.168.168.42
uname -a          # Linux with modern kernel

# Check disk space
df -h /opt        # Need 100+ MB available

# Verify required commands
for cmd in bash git curl rsync tar gzip; do
  command -v $cmd || echo "Missing: $cmd"
done


Step 2: Execute Deployment Script
──────────────────────────────────

# Transfer deployment script to worker (via USB, network share, or physical access)
# Then on dev-elevatediq:

sudo bash deploy-standalone.sh

# Or without sudo prompt (if user in sudoers):
bash deploy-standalone.sh


Step 3: Monitor Deployment Progress
────────────────────────────────────

# In real-time:
tail -f /opt/automation/audit/deployment-*.log

# After completion:
cat /opt/automation/audit/deployment-*.log | grep -E "(✓|✅|❌|ERROR)"


Step 4: Verify Deployment Success
──────────────────────────────────

# Check deployment directory structure
ls -laR /opt/automation/

# Expected output:
# /opt/automation/
# ├── k8s-health-checks/
# │   ├── cluster-readiness.sh
# │   ├── cluster-stuck-recovery.sh
# │   └── validate-multicloud-secrets.sh
# ├── security/
# │   └── audit-test-values.sh
# ├── multi-region/
# │   └── failover-automation.sh
# ├── core/
# │   ├── credential-manager.sh
# │   ├── orchestrator.sh
# │   └── deployment-monitor.sh
# └── audit/
#     └── deployment-*.log


═════════════════════════════════════════════════════════════════════════════
5. POST-DEPLOYMENT VERIFICATION
═════════════════════════════════════════════════════════════════════════════

Verify Script Execution
──────────────────────

# Check all scripts are executable
find /opt/automation -name "*.sh" -type f | while read f; do
  [ -x "$f" ] && echo "✓ $f" || echo "✗ $f (not executable)"
done

# Test syntax of all scripts
for f in /opt/automation/*/*.sh; do
  bash -n "$f" && echo "✓ Syntax: $(basename $f)" || echo "✗ Syntax error: $f"
done

# Get file details
ls -la /opt/automation/*/*.sh | awk '{print $1, $9}'


Test Individual Scripts
───────────────────────

# Test kubectl connectivity
bash /opt/automation/k8s-health-checks/cluster-readiness.sh --check-only

# Test credential manager
bash /opt/automation/core/credential-manager.sh --verify

# Test security audit (read-only)
bash /opt/automation/security/audit-test-values.sh --report

# Monitor current deployments
bash /opt/automation/core/deployment-monitor.sh --status


Verify Deployment Log
─────────────────────

# View deployment summary
tail -50 /opt/automation/audit/deployment-*.log | head -20

# Check for errors
grep -i error /opt/automation/audit/deployment-*.log

# Check for warnings
grep -i warning /opt/automation/audit/deployment-*.log


═════════════════════════════════════════════════════════════════════════════
6. SCHEDULING & AUTOMATION
═════════════════════════════════════════════════════════════════════════════

Setup Cron Jobs
───────────────

# Edit crontab
sudo crontab -e

# Add health checks (every 5 minutes)
*/5 * * * * /opt/automation/k8s-health-checks/cluster-readiness.sh --quiet >> /var/log/automation/health-checks.log 2>&1

# Add security audit (daily at 2 AM)
0 2 * * * /opt/automation/security/audit-test-values.sh --report > /var/log/automation/audit-$(date +\%Y\%m\%d).log 2>&1

# Add credential rotation (every 6 hours)
0 */6 * * * /opt/automation/core/credential-manager.sh --rotate >> /var/log/automation/cred-rotation.log 2>&1

# Add deployment monitoring (continuous)
@reboot /opt/automation/core/deployment-monitor.sh --daemon >> /var/log/automation/deployment-monitor.log 2>&1


Monitor Automations
───────────────────

# View cron job execution
sudo journalctl -u cron --since today

# Check automation logs
ls -lh /var/log/automation/

# Monitor in real-time
watch -n 5 'ls -lah /opt/automation/audit/'


═════════════════════════════════════════════════════════════════════════════
7. TROUBLESHOOTING
═════════════════════════════════════════════════════════════════════════════

Deployment Failed
─────────────────

Problem: Script exits with error
Solution:
  1. Check prerequisites are met:
     bash deploy-standalone.sh  # Re-run with detailed output
  2. Review deployment log:
     cat /opt/automation/audit/deployment-*.log
  3. Check disk space:
     df -h /opt
  4. Manual deployment fallback:
     # Clone repo manually and copy scripts

Problem: Insufficient permissions
Solution:
  1. Check sudo access:
     sudo -l | grep NOPASSWD
  2. Add user to sudoers:
     sudo usermod -aG sudo $USER
  3. Or run entire deployment with sudo:
     sudo bash deploy-standalone.sh


Script Execution Issues
──────────────────────

Problem: "Permission denied" when running scripts
Solution:
  1. Check if executable:
     ls -la /opt/automation/*/*.sh
  2. Make executable if needed:
     sudo chmod +x /opt/automation/*/*.sh

Problem: "Command not found" inside script
Solution:
  1. Verify required binaries exist:
     command -v kubectl
     command -v aws
     command -v az
  2. Ensure required tools installed:
     sudo apt update && sudo apt install -y kubectl
  3. Add to PATH if needed:
     export PATH=/usr/local/bin:$PATH


Health Check Issues
───────────────────

Problem: cluster-readiness.sh fails
Solution:
  1. Verify kubectl access:
     kubectl cluster-info
  2. Check kubeconfig:
     echo $KUBECONFIG
     ls -la ~/.kube/config
  3. Verify cluster status:
     kubectl get nodes
     kubectl get cs

Problem: validate-multicloud-secrets.sh fails
Solution:
  1. Verify cloud credentials:
     aws sts get-caller-identity
     az account show
     gcloud auth list
  2. Check secret access:
     aws secretsmanager list-secrets
  3. Test connectivity:
     ping kms.amazonaws.com


═════════════════════════════════════════════════════════════════════════════
8. MONITORING & ADMINISTRATION
═════════════════════════════════════════════════════════════════════════════

Monitor Automation Health
─────────────────────────

# Check if any automation scripts are running
ps aux | grep -E '(cluster-readiness|failover|credential-manager)'

# Monitor resource usage during automation
watch -n 1 'ps aux | grep automation'

# Check disk usage of logs
du -sh /opt/automation/audit/

# Monitor system resources
watch -n 5 'free -h; df -h /opt'


Collect Diagnostics
───────────────────

# Create diagnostic bundle
mkdir -p /tmp/automation-diagnostics
cp -r /opt/automation/audit /tmp/automation-diagnostics/
cp /var/log/automation/* /tmp/automation-diagnostics/ 2>/dev/null || true
tar -czf /tmp/automation-diagnostics.tar.gz /tmp/automation-diagnostics/

# System info
echo "=== System Info ===" > /tmp/system-info.txt
uname -a >> /tmp/system-info.txt
lsb_release -a >> /tmp/system-info.txt 2>/dev/null || true
df -h >> /tmp/system-info.txt


Security & Permissions
──────────────────────

# Verify directory permissions
ls -ld /opt/automation
find /opt/automation -type d -exec ls -ld {} \;

# Audit who has executed scripts
stat /opt/automation/*/*.sh | grep Access

# Check script integrity
cd /opt/automation
find . -name "*.sh" -exec sha256sum {} \; > /tmp/script-checksums.txt


═════════════════════════════════════════════════════════════════════════════
9. ROLLBACK PROCEDURES
═════════════════════════════════════════════════════════════════════════════

If Issues Occur After Deployment
─────────────────────────────────

Complete Removal:
  # Stop any running automations
  pkill -f /opt/automation
  
  # Remove installation
  sudo rm -rf /opt/automation/
  
  # Clean logs
  sudo rm -rf /var/log/automation/
  
  # Remove cron jobs
  sudo crontab -e  # Remove automation entries

Partial Revert:
  # Keep logs and configs, remove scripts
  sudo rm -rf /opt/automation/{core,security,multi-region}
  
  # Redeploy specific component
  bash deploy-standalone.sh  # Runs full deployment again

Archive Before Changes:
  # Backup current installation
  sudo tar -czf /opt/automation-backup-$(date +%Y%m%d-%H%M%S).tar.gz /opt/automation/
  
  # Then make changes
  # If problems, restore:
  sudo tar -xzf /opt/automation-backup-*.tar.gz -C /


═════════════════════════════════════════════════════════════════════════════
10. SUPPORT & ESCALATION
═════════════════════════════════════════════════════════════════════════════

For Deployment Issues:

1. Check deployment log:
   tail -100 /opt/automation/audit/deployment-*.log

2. Review Prerequisites:
   Check all items from Section 3

3. Verify Script Syntax:
   bash -n /opt/automation/*/*.sh

4. Manual Verification:
   docker ps  # If containerized
   kubectl version  # If using k8s
   aws sts get-caller-identity  # If using AWS

5. Request diagnostics package:
   tar -czf automation-diagnostics.tar.gz \
     /opt/automation/audit/ \
     /var/log/automation/ \
     /tmp/system-info.txt \
     /tmp/script-checksums.txt

Contact Points:
  • GitHub Issues: https://github.com/kushin77/self-hosted-runner/issues
  • Email: [support-email]
  • Slack: [support-channel]


═════════════════════════════════════════════════════════════════════════════

Document Version: 1.0
Last Updated: $(date +%Y-%m-%d)
Target: dev-elevatediq (192.168.168.42)
Status: Ready for Deployment

EOF
