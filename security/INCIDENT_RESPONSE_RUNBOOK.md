# Security Incident Response & Runbook (FAANG-Grade)

## 1. CRITICAL INCIDENT RESPONSE PROCEDURES

### 1.1 Confirmed Breach Detection

**Detection Triggers:**
- Unauthorized credential access detected in audit logs
- Spike in failed authentication attempts (>100 in 5 minutes)
- Unexpected privilege escalation detected
- Suspicious outbound data transfer (>1GB outside normal pattern)
- Potential ransomware activity (rapid file encryption)

**30-SECOND RESPONSE:**
1. **IMMEDIATE ISOLATION**
   ```bash
   # Revoke all active API keys and sessions
   gcloud secrets versions destroy <version> --secret=github-token
   gcloud secrets versions destroy <version> --secret=aws-access-key-id
   
   # Isolate compromised nodes
   kubectl cordon <node-name>  # Prevent new pod scheduling
   kubectl drain <node-name> --ignore-daemonsets  # Evict existing pods
   ```

2. **KILL SWITCH ACTIVATION**
   ```bash
   # Immediate credential rotation (pre-automated)
   bash scripts/secrets/rotate-credentials.sh all --apply --force
   
   # Revoke service account access
   gcloud iam service-accounts disable <compromised-sa>
   ```

3. **NOTIFY ON-CALL**
   ```bash
   # Alert incident response team (automated)
   # - PagerDuty/AlertManager triggers automatically
   # - Slack channels notified
   # - Executive escalation initiated
   ```

**5-MINUTE RESPONSE:**
1. **FORENSICS COLLECTION**
   ```bash
   # Collect all audit logs
   kubectl logs -n kube-system -l component=kubelet --tail=10000 > kubelet-logs.txt
   
   # Export Cloud Audit Logs
   gcloud logging read "resource.type=k8s_cluster AND severity>=ERROR" \
     --limit=10000 --format=json > audit-logs.json
   
   # Collect container logs (before teardown)
   kubectl logs <pod-name> --all-containers > pod-logs.txt
   ```

2. **CONTAINMENT**
   ```bash
   # Revoke all Vault tokens
   curl -X LIST -H "X-Vault-Token: $VAULT_TOKEN" \
     https://vault.company.com/v1/auth/token/accessors | jq '.data.keys[]' | \
     xargs -I {} curl -X DELETE -H "X-Vault-Token: $VAULT_TOKEN" \
     https://vault.company.com/v1/auth/token/revoke/{}
   
   # Block high-risk IPs at edge
   gcloud compute security-policies rules create 9000 \
     --action "deny-403" \
     --security-policy=default \
     --conditions="origin-region-code=XX"
   ```

3. **PRESERVATION OF EVIDENCE**
   ```bash
   # Create immutable backup of logs and forensics
   gsutil cp -r gs://evidence/* gs://evidence-archive/$(date +%Y%m%d-%T)/
   gsutil retention set -s gs://evidence-archive/
   # Enable Object Lock (WORM) on archive bucket
   ```

**ESCALATION MATRIX:**
- **CRITICAL (Data Loss/Breach):** Level 4 (CTO/CISO)
- **HIGH (Credentials Exposed):** Level 3 (VP Security)
- **MEDIUM (Intrusion Detection):** Level 2 (Security Lead)
- **LOW (Policy Violation):** Level 1 (Team Lead)

---

## 2. CREDENTIAL COMPROMISE RESPONSE

If GitHub PAT is compromised:
```bash
#!/bin/bash
# 1. Revoke compromised token
gh auth logout
gh auth login

# 2. Rotate in GSM immediately
GITHUB_PAT="<NEW_TOKEN>" bash scripts/secrets/rotate-credentials.sh github --apply

# 3. Scan repository for exposed token usage
gitleaks detect --no-git --source .

# 4. Audit all commits from given time period
git log --since="2 hours ago" --oneline --name-only

# 5. Force re-authenticate all CI/CD
gcloud builds cancel $(gcloud builds list --filter="status=QUEUED or status=WORKING" --format="value(id)")
```

If AWS keys are compromised:
```bash
#!/bin/bash
# 1. Disable compromised IAM user
aws iam update-access-key --access-key-id=$OLD_KEY --status Inactive

# 2. Rotate credentials
AWS_ACCESS_KEY_ID="$NEW_KEY" AWS_SECRET_ACCESS_KEY="$NEW_SECRET" \
  bash scripts/secrets/rotate-credentials.sh aws --apply

# 3. Review CloudTrail for suspicious activity
aws cloudtrail lookup-events \
  --lookupAttributes AttributeKey=AccessKeyId,AttributeValue=$OLD_KEY \
  --max-results 50

# 4. Revoke all temporary credentials (STS tokens)
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[InstanceId]" \
  --output text | xargs -I {} aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=instanceids,Values={}" \
  --parameters "commands=['rm -f ~/.aws/credentials']"
```

---

## 3. DATA EXFILTRATION RESPONSE

**Detection:**
- Network egress spike >100x normal
- S3 download activity from unusual IPs
- Large database exports initiated

**Containment:**
```bash
#!/bin/bash
# 1. Immediately block outbound traffic
gcloud compute firewall-rules create emergency-deny-egress \
  --direction=EGRESS \
  --priority=0 \
  --destination-ranges=0.0.0.0/0 \
  --deny=all

# 2. Kill all outbound connections
sudo iptables -P OUTPUT DROP
sudo iptables -A OUTPUT -d 127.0.0.1 -j ACCEPT
sudo iptables -A OUTPUT -d <internal-ranges> -j ACCEPT

# 3. Dump network connections for forensics
netstat -tupan > current-connections.txt
ss -tupan > current-sockets.txt
lsof -i > open-files.txt

# 4. Enable packet capture for investigation
sudo tcpdump -i eth0 -w incidents/capture-$(date +%s).pcap

# 5. Restore normal egress after investigation
gcloud compute firewall-rules delete emergency-deny-egress
```

---

## 4. RANSOMWARE RESPONSE

**Detection:**
- Rapid file encryption (>1000 files/minute)
- Common ransomware file extensions (.encrypted, .locked, .ransom)
- Master boot record modification attempts

**Aggressively:**
```bash
#!/bin/bash
# 1. IMMEDIATE KILL SWITCH **
killall -9 kubectl  # Stop all orchestration
systemctl stop docker  # Stop container runtime
systemctl stop kubelet  # Stop node

# 2. Snapshot immediately (for forensics & recovery)
gcloud compute disks snapshot <disk-name> \
  --snapshot-names=forensics-$(date +%s)

# 3. Network isolation (kill all connections)
sudo ip link set eth0 down

# 4. Recovery from immutable backups
gcloud compute disks create restored-disk \
  --source-snapshot=backup-$(date -d "1 day ago" +%Y%m%d)
```

---

## 5. INSIDER THREAT RESPONSE

When employee/contractor potentially exfiltrating data:

```bash
#!/bin/bash
# 1. Immediately revoke credentials
gcloud iam service-accounts keys list \
  --iam-account=$SERVICE_ACCOUNT | jq '.keys[].name' | \
  xargs -I {} gcloud iam service-accounts keys delete {}

# 2. Kill all active sessions
kubectl delete all -n default -l user=$USERNAME
pkill -9 -u $UID

# 3. Revoke SSH/API access
gcloud compute project-info remove-iam-policy-binding $(gcloud config get-value project) \
  --member=user:$EMAIL --role=roles/compute.admin

# 4. Audit all actions (immutable)
gcloud logging read "protoPayload.authenticationInfo.principalEmail=$EMAIL" \
  --limit=100000 --format=json | jq > incidents/insider-audit-$(date +%s).json

# 5. Legal preservation notice
echo "PRESERVE ALL DATA - Legal Hold in Effect" > HOLD_NOTICE.txt
find /home/$USERNAME -exec touch {} \;  # Update access times
```

---

## 6. COMPLIANCE VIOLATION RESPONSE

**PCI DSS Violation (Credit Card Data Exposure):**
```bash
# 1. Identify affected systems
grep -r "4[0-9]{12}(?:[0-9]{3})" --include="*.log" --include="*.txt" . > pci-findings.txt

# 2. Revoke access certificates used
gcloud compute ssl-certificates delete $AFFECTED_CERT

# 3. Generate compliance report
bash scripts/security/generate-compliance-report.sh --incident

# 4. Notify acquiring bank within SLA
# < 72 hours for PCI DSS
```

**HIPAA Violation (Protected Health Information):**
```bash
# 1. Identify scope of breach
grep -r "MRN\|SSN" logs/ > phi-findings.txt

# 2. Encrypt all remaining PHI
openssl enc -aes-256-cbc -salt -in data.csv -out data.csv.enc

# 3. Generate breach notification
echo "Breach Notification Required - $(wc -l < phi-findings.txt) records"

# 4. Report to OCR (Office for Civil Rights) within 60 days
```

---

## 7. ATTACK PLAYBOOK: DDoS

**Detection:**
- Request volume >10x baseline
- Spike in 404/403 errors
- Target: specific endpoint (not distributed)

**Response:**
```bash
#!/bin/bash
# 1. Activate DDoS protection
gcloud compute security-policies rules create 10000 \
  --action "rate-based-ban" \
  --rate-limit-options=enforce-on-key=IP \
  --ban-duration-sec=600

# 2. Scale up capacity
gcloud compute instance-groups managed set-autoscaling prod-group \
  --max-num-replicas=100 --min-num-replicas=10

# 3. Enable Cloud Armor
kubectl patch ingress prod-ingress \
  -p '{"metadata":{"annotations":{"cloud-armor-policy":"prod-policy"}}}'

# 4. Route suspicious traffic to honeypot
gcloud compute routes create honeypot \
  --destination-range=0.0.0.0/0 \
  --next-hop-gateway=default-internet-gateway

# 5. Monitor attack progression
kubectl port-forward svc/prometheus 9090:9090 &
# Open http://localhost:9090 to view metrics
```

---

## 8. POST-INCIDENT REPORTING

**RCA (Root Cause Analysis) Template:**
```markdown
# Incident Report: [INCIDENT_ID]

## Timeline
| Time | Event | Severity |
|------|-------|----------|
| 14:35 | ALERT: Unusual login | P3 |
| 14:37 | Confirmed: Credentials exposed | P1 |
| 14:39 | Credentials rotated | - |
| 14:45 | Investigation complete | - |

## Root Cause
[Technical analysis - why did this happen?]

## Detection Gaps
[What didn't catch this?]

## Prevention
[Changes to prevent recurrence]

## Action Items
1. [ ] Implement X [Owner: Y, DueDate: Z]
2. [ ] Update runbook
3. [ ] Security training

## Cost Impact
- Incident Response: $X
- Remediation: $Y
- Customer Notification: $Z
- Total: $SUM
```

---

## 9. TESTING & DRILLS

**Monthly Security Drills:**
```bash
# Schedule monthly incident response drill
# Scenario: "Find the simulated breach"

# Inject fake suspicious logs
echo "FAKE: Unauthorized AWS access from 1.2.3.4" >> /var/log/audit.log

# Measure response time
time bash scripts/security/incident-response.sh --drill

# Measure team effectiveness
# - Time to detection
# - Time to containment
# - Time to remediation
# - False positive rate
```

---

## 10. SECURITY COMMUNICATION TEMPLATES

**Customer Notification Email (Data Breach):**
```
Subject: Important Security Notice [#INCIDENT_ID]

Dear Customer,

We are writing to inform you of a potential security incident affecting your data...

What happened:
- [Brief description]
- Incident ID: [ID]
- Detection Time: [TIME]
- Date Range Affected: [DATES]

What we did:
- [Immediate actions]
- [Investigation findings]
- [Preventive measures]

What you should do:
- Change password immediately
- Monitor account for suspicious activity
- Contact us if you see anything odd

Questions?
- Security Team: security@company.com
- Incident Hotline: +1-XXX-XXX-XXXX
```

---

## Quick Reference Commands

```bash
# EMERGENCY CREDENTIAL REVOKE
export GSM_PROJECT=nexusshield-prod
echo -n "" | gcloud secrets versions add github-token --data-file=- --project=$GSM_PROJECT

# EMERGENCY NETWORK ISOLATION
gcloud compute firewall-rules create emergency-lockdown \
  --direction=EGRESS --action=DENY --rules=all \
  --priority=0

# CHECK AUDIT LOGS FOR COMPROMISE INDICATORS
gcloud logging read \
  '(protoPayload.methodName="compute.instances.setServiceAccount" OR \
    protoPayload.methodName="iam.serviceAccounts.getAccessToken" OR \
    protoPayload.methodName="storage.buckets.delete")' \
  --limit=1000 --format=json

# FORCE CREDENTIAL ROTATION
bash scripts/secrets/rotate-credentials.sh all --apply --force

# MOUNT FORENSICS DISK
gcloud compute instances attach-disk forensics-instance \
  --disk=compromised-disk

# ENABLE IMMUTABLE AUDIT LOGGING
gsutil retention set 30d gs://audit-logs-archive
gsutil object-lock set gs://audit-logs-archive
```

---

## Escalation Contacts

- **Security On-Call Pager:** [PagerDuty URL]
- **CISO:** ciso@company.com
- **Legal:** legal@company.com
- **CEO:** (for breach notification)
- **FBI Cyber Division:** (for APT incidents)

---

*Last Updated: 2026-03-13*  
*Next Update: 2026-03-20*  
*Exercises: Monthly*
