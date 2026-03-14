#!/bin/bash
#
# SERVICE ACCOUNT SSH SETUP GUIDE
# Configure SSH authentication for worker node deployment
#

cat << 'EOF'

╔════════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║          SERVICE ACCOUNT SSH SETUP - QUICK GUIDE                      ║
║                                                                        ║
║  Configure SSH authentication for automated worker node deployment   ║
║  Target: dev-elevatediq (192.168.168.42)                            ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝

═══════════════════════════════════════════════════════════════════════════

STEP 1: GENERATE SSH KEY PAIR
─────────────────────────────

On your developer machine, create an SSH key for the automation service account:

  # Generate new SSH key (automation account)
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/automation -N "" -C "automation@dev-elevatediq"

  # Or generate for different service account
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/ci-deploy -N "" -C "ci-deploy@dev-elevatediq"

Expected files:
  ~/.ssh/automation          (PRIVATE KEY - keep secure!)
  ~/.ssh/automation.pub      (PUBLIC KEY - safe to share)

Verify permissions:
  ls -la ~/.ssh/automation
  # Should show: -rw------- 1 user user (600 permissions)

═══════════════════════════════════════════════════════════════════════════

STEP 2: DEPLOY PUBLIC KEY TO WORKER NODE
─────────────────────────────────────────

Transfer the PUBLIC key to the worker node and authorize it.

METHOD A: Using ssh-copy-id (easiest if you have SSH access)
  
  ssh-copy-id -i ~/.ssh/automation.pub automation@192.168.168.42
  
  # When prompted, enter the password for automation account
  # This automatically adds the key to ~/.ssh/authorized_keys

METHOD B: Manual Transfer (if ssh-copy-id not available)
  
  1. Copy the public key file to the worker:
     scp ~/.ssh/automation.pub automation@192.168.168.42:~/
  
  2. SSH to worker and authorize the key:
     ssh automation@192.168.168.42
     cd ~
     cat automation.pub >> .ssh/authorized_keys
     rm automation.pub
     chmod 600 .ssh/authorized_keys
  
  3. Verify (should not prompt for password):
     ssh -i ~/.ssh/automation automation@192.168.168.42 echo "Success"

METHOD C: USB/Admin Transfer (if no SSH access yet)
  
  1. Copy public key to USB:
     cp ~/.ssh/automation.pub /media/usb/
  
  2. On worker node (manual transfer):
     cat /media/usb/automation.pub >> ~/.ssh/authorized_keys
     chmod 600 ~/.ssh/authorized_keys

═══════════════════════════════════════════════════════════════════════════

STEP 3: VERIFY SSH KEY WORKS
────────────────────────────

Test the SSH key authentication:

  # Test without password (should succeed)
  ssh -i ~/.ssh/automation automation@192.168.168.42 echo "Connected!"
  
  Expected output: Connected!

  # Get more details if it fails
  ssh -i ~/.ssh/automation -v automation@192.168.168.42 echo "Test"

═══════════════════════════════════════════════════════════════════════════

STEP 4: CONFIGURE DEPLOYMENT SCRIPT
───────────────────────────────────

Now you can use the deployment script:

  # Default: Uses ~/.ssh/automation
  bash deploy-worker-node.sh

  # With custom service account
  SERVICE_ACCOUNT=github-actions bash deploy-worker-node.sh

  # With explicit key path
  SSH_KEY=~/.ssh/my-custom-key bash deploy-worker-node.sh

═══════════════════════════════════════════════════════════════════════════

OPTIONAL: ADVANCED CONFIGURATION
─────────────────────────────────

SSH Config File (~/.ssh/config)
  
  Add this to ~/.ssh/config for easier access:
  
  Host dev-worker
    HostName 192.168.168.42
    User automation
    IdentityFile ~/.ssh/automation
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
  
  Then use:
  ssh dev-worker
  ssh dev-worker ls /opt/automation

Multiple Service Accounts

  Generate separate keys for different accounts:
  
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/github-actions -N ""
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/ci-deploy -N ""
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/monitoring -N ""
  
  Deploy to each:
  SERVICE_ACCOUNT=github-actions bash deploy-worker-node.sh
  SERVICE_ACCOUNT=ci-deploy bash deploy-worker-node.sh
  SERVICE_ACCOUNT=monitoring bash deploy-worker-node.sh

Key Passphrase (optional security)
  
  If you want to protect the key with a passphrase:
  
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/automation -C "automation@dev-elevatediq"
  # When prompted: Enter passphrase (can be empty or enter a passphrase)
  
  Then use with agent:
  ssh-add ~/.ssh/automation  # Enter passphrase once
  ssh automation@192.168.168.42  # No passphrase needed

═══════════════════════════════════════════════════════════════════════════

TROUBLESHOOTING
───────────────

Problem: "Permission denied (publickey)"
Solution:
  1. Verify public key is on worker:
     ssh automation@192.168.168.42 cat ~/.ssh/authorized_keys
  
  2. Check key permissions (should be 600):
     ssh automation@192.168.168.42 ls -la ~/.ssh/authorized_keys
  
  3. Re-copy the key:
     ssh-copy-id -i ~/.ssh/automation.pub automation@192.168.168.42

Problem: "No public key found"
Solution:
  1. Check local key exists:
     ls -la ~/.ssh/automation
  
  2. If missing, regenerate:
     ssh-keygen -t rsa -b 4096 -f ~/.ssh/automation -N ""
  
  3. Deploy public key to worker

Problem: "Connection refused"
Solution:
  1. Verify host is reachable:
     ping 192.168.168.42
  
  2. Check SSH port:
     ssh -i ~/.ssh/automation automation@192.168.168.42 -p 22 echo "test"
  
  3. Verify SSH service running on worker:
     ps aux | grep sshd

Problem: SSH key not detected by deployment script
Solution:
  1. Check script looks in right location:
     ls ~/.ssh/automation
  
  2. Or explicitly specify key path:
     SSH_KEY=~/.ssh/automation bash deploy-worker-node.sh
  
  3. Debug with verbose output:
     bash -x deploy-worker-node.sh 2>&1 | head -50

═══════════════════════════════════════════════════════════════════════════

SECURITY BEST PRACTICES
──────────────────────

1. Key Storage
   ✅ Keep private keys in ~/.ssh/ only
   ✅ Use restrictive permissions (600)
   ✅ Never commit keys to git
   ✅ Back up keys securely

2. Key Management
   ✅ Use separate keys for different services
   ✅ Rotate keys periodically
   ✅ Monitor key usage
   ✅ Remove old keys when no longer needed

3. SSH Access
   ✅ Use service accounts for automation
   ✅ Restrict service account privileges
   ✅ Monitor SSH logs (/var/log/auth.log)
   ✅ Use SSH key agent (ssh-add) for passphrases

4. Deployment Security
   ✅ Run deployment from secure network
   ✅ Use HTTPS for git clone
   ✅ Verify script checksums
   ✅ Audit deployment logs

═══════════════════════════════════════════════════════════════════════════

QUICK REFERENCE
───────────────

Generate key:
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/automation -N ""

Deploy public key:
  ssh-copy-id -i ~/.ssh/automation.pub automation@192.168.168.42

Test SSH:
  ssh -i ~/.ssh/automation automation@192.168.168.42 echo "Works"

Run deployment:
  bash deploy-worker-node.sh

Check deployment:
  ssh -i ~/.ssh/automation automation@192.168.168.42 ls /opt/automation

View logs:
  ssh -i ~/.ssh/automation automation@192.168.168.42 tail /opt/automation/audit/deployment-*.log

═══════════════════════════════════════════════════════════════════════════

COMPLETION CHECKLIST
────────────────────

Setup Verification:
  ☐ SSH key pair generated (~/.ssh/automation)
  ☐ Public key deployed to worker
  ☐ SSH connection works without password
  ☐ Service account created on worker (if not exists)
  ☐ SSH authorized_keys has public key
  ☐ deployment script can find SSH key

Test Deployment:
  ☐ Run: bash deploy-worker-node.sh
  ☐ No SSH connection errors
  ☐ All 8 scripts deploy successfully
  ☐ Verification passes (12/12 checks)
  ☐ Remote deployment complete message

Post-Deployment:
  ☐ /opt/automation directory exists on worker
  ☐ All 8 scripts present and executable
  ☐ Audit logs created and readable
  ☐ Can run scripts remotely: ssh ... /opt/automation/k8s-health-checks/cluster-readiness.sh

═══════════════════════════════════════════════════════════════════════════

NEXT STEPS
──────────

1. Generate SSH key:
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/automation -N ""

2. Deploy public key:
   ssh-copy-id -i ~/.ssh/automation.pub automation@192.168.168.42

3. Test SSH:
   ssh -i ~/.ssh/automation automation@192.168.168.42 echo "Success"

4. Run deployment:
   bash deploy-worker-node.sh

5. Verify:
   ssh -i ~/.ssh/automation automation@192.168.168.42 find /opt/automation -name "*.sh" | wc -l

═══════════════════════════════════════════════════════════════════════════

Document Version: 1.0
Target: dev-elevatediq (192.168.168.42)
Status: Ready to use

EOF
