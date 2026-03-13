# On-Premises Redundancy and VPN Failover Runbook

## Overview

This runbook documents the on-premises to Google Cloud redundancy infrastructure with:
- **Primary Connection**: Cloud Interconnect (dedicated high-bandwidth)
- **Backup Connection**: HA VPN tunnel (automatic failover)
- **SSH Key Management**: HashiCorp Vault with 30-day rotation
- **Automatic Failover**: BGP-based routing failover
- **RPO**: Near-zero (replication-based)
- **RTO**: 5-10 minutes (automatic)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Initial Setup and Verification](#initial-setup-and-verification)
3. [SSH Key Management](#ssh-key-management)
4. [Failover Procedures](#failover-procedures)
5. [Monitoring and Alerts](#monitoring-and-alerts)
6. [Troubleshooting](#troubleshooting)
7. [Runbook Index](#runbook-index)

---

## Architecture Overview

### Network Connectivity Layers

```
On-Premises Network (10.40.0.0/16)
    ├─ Primary Gateway (203.0.113.12)
    │   ├─ Cloud Interconnect
    │   │   └─ Direct Connection (50Mbps → 10Gbps)
    │   │       └─ GCP Router (ASN: 64512) - us-central1
    │   │
    │   └─ Backup VPN (IKEv2)
    │       └─ HA VPN Gateway - us-east1
    │
    └─ Secondary Gateway (203.0.113.13)
        └─ Backup VPN
            └─ HA VPN Gateway - us-east1
```

### Failover Logic (BGP-Based)

```
Normal State:
  On-Premises → [Interconnect - Primary Route] → GCP

Interconnect Failure:
  1. BGP detects peer down (timeout: 60 seconds)
  2. BGP withdraws routes from Interconnect
  3. BGP re-announces routes via VPN
  4. On-Premises routes 100% traffic via VPN
  5. Estimated failover time: 60-300 seconds
```

---

## Initial Setup and Verification

### 1. Pre-Deployment Checklist

```bash
# Verify on-premises gateway IPs are registered with Google Cloud
gcloud compute interconnects describe nexusshield-primary-interconnect

# Verify external VPN gateway is configured
gcloud compute external-vpn-gateways describe nexusshield-onprem-external-vpn

# Verify VPN tunnels are created
gcloud compute vpn-tunnels list --filter="name:nexusshield*"
```

### 2. Deploy Infrastructure via Terraform

```bash
cd terraform

# Validate configuration
terraform validate -var="onprem_redundancy_enabled=true"

# Plan infrastructure
terraform plan -var="onprem_redundancy_enabled=true" \
  -out=onprem-redundancy.plan

# Apply configuration
terraform apply onprem-redundancy.plan

# Verify outputs
terraform output
```

### 3. Initial BGP Verification

```bash
# Check BGP peers for primary interconnect
gcloud compute routers describe nexusshield-onprem-primary-router \
  --region=us-central1 \
  --format="value(bgp.peers[])"

# Check BGP states
gcloud compute routers get-status nexusshield-onprem-primary-router \
  --region=us-central1 \
  --format="value(result.bgp_peer_status[])"
```

### 4. Test Connectivity

```bash
# From on-premises, ping GCP network
ONPREM_IP=$(dig +short @8.8.8.8 onprem.nexusshield.cloud | head -1)
GCP_IP=$(dig +short @8.8.8.8 gcp.nexusshield.cloud | head -1)

ping $GCP_IP  # Should respond

# Test VPN tunnel status (from GCP)
gcloud compute vpn-tunnels describe nexusshield-backup-vpn-tunnel-1 \
  --region=us-east1 --format="value(status)"
```

---

## SSH Key Management

### Vault-Based SSH Certificates

**Benefits:**
- No static key files to manage
- Centralized access control
- Automatic rotation (30-day cycle)
- Audit trail of all access
- Per-user isolation

### 1. Generate SSH Certificate

```bash
# Request SSH certificate from Vault
vault write -field=signed_key ssh/issue/onprem-deployer \
  username=ubuntu \
  ip_addresses=10.40.1.100 > ~/.ssh/id_rsa-vault.pub

# or via HTTP API
curl -X POST https://vault.nexusshield.cloud/v1/ssh/issue/onprem-deployer \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -d '{"username":"ubuntu","ip_addresses":"10.40.1.100"}' | jq '.data.signed_key'
```

### 2. Use SSH Certificate

```bash
# Get certificate validity period
ssh-keygen -L -f ~/.ssh/id_rsa-vault.pub | grep -A5 "Validity"

# Example output:
#   Valid after:    2026-03-13T15:00Z
#   Valid before:   2026-04-12T15:00Z (30-day rotation)

# SSH without password (if configured for cert-based auth)
ssh -i ~/.ssh/id_rsa-vault.pub ubuntu@10.40.1.100
```

### 3. Automatic Key Rotation

```bash
# Cloud Scheduler triggers rotation weekly
# Job runs: Every Sunday at 2 AM UTC

# To manually trigger rotation
curl -X POST https://scheduler.googleapis.com/v1/projects/PROJECT_ID/locations/us-central1/jobs/nexusshield-ssh-key-rotation:resume \
  -H "Authorization: Bearer $(gcloud auth print-access-token)"

# Verify rotation happened
gcloud logging read "resource.type=cloud_scheduler_job AND resource.labels.job_id=nexusshield-ssh-key-rotation" \
  --limit 5 --format=json | jq '.[].textPayload'
```

### 4. Troubleshooting SSH Certificate Issues

```bash
# Check certificate validity
ssh-keygen -L -f ~/.ssh/id_rsa-vault.pub

# Test SSH connection with verbose output
ssh -v -i ~/.ssh/id_rsa-vault.pub ubuntu@10.40.1.100

# Check Vault audit log
vault audit list
vault audit logs ssh

# Check system auth logs on remote machine
ssh ubuntu@10.40.1.100 "sudo tail -20 /var/log/auth.log | grep ssh"
```

---

## Failover Procedures

### Automatic Failover (System-Initiated)

**When triggered:**
- Primary Interconnect connection lost for > 60 seconds
- BGP peer down notification received
- VPN tunnel active and healthy

**What happens automatically:**
1. BGP detects primary route failure
2. Primary routes withdrawn from routing table
3. Secondary routes via VPN are re-announced
4. Traffic automatically routes over VPN
5. System health checks validate VPN is stable
6. Alerts notify ops team

### Manual Failover to VPN (Operator-Initiated)

**When to use:**
- Planned maintenance on Interconnect
- Interconnect upgrade required
- ISP maintenance window
- Testing failover procedures (staging only!)

```bash
# Step 1: Verify VPN tunnel health
gcloud compute vpn-tunnels describe nexusshield-backup-vpn-tunnel-1 \
  --region=us-east1 --format="value(status)"

gcloud compute vpn-tunnels describe nexusshield-backup-vpn-tunnel-2 \
  --region=us-east1 --format="value(status)"

# Expected output: UP (or FIRST_HANDSHAKE)

# Step 2: Manually withdraw Interconnect routes (optional)
# This forces traffic over VPN

# Via Terraform (disable Interconnect attachment)
terraform apply -var="enable_primary_interconnect=false"

# Or via gcloud
gcloud compute interconnects attachments delete nexusshield-primary-interconnect-ATTACHMENT_ID \
  --region=us-central1 --quiet

# Step 3: Monitor failover (take 1-5 minutes)
watch 'gcloud compute routers get-status nexusshield-onprem-backup-router --region=us-east1 --format="table(result.bgp_peer_status[].(peer_ip_address, state))"'

# Step 4: Verify connectivity is still working
GCP_TEST_IP=$(dig +short gcp-test.nexusshield.cloud | head -1)
ping $GCP_TEST_IP

# Step 5: Monitor application logs for disruptions
tail -f /var/log/nexusshield/api.log | grep -i "error\|timeout\|connection"

# Step 6: After confirming stability, re-enable Interconnect
terraform apply -var="enable_primary_interconnect=true"
```

### Failback to Primary Interconnect

**After Interconnect is repaired:**

```bash
# Step 1: Verify Interconnect is healthy
gcloud compute interconnects-attachments describe ATTACHMENT_ID \
  --format="value(operationalStatus)"

# Expected: UP

# Step 2: Re-enable Interconnect routes
terraform apply -var="enable_primary_interconnect=true"

# Step 3: Monitor BGP re-convergence
watch 'gcloud compute routers get-status nexusshield-onprem-primary-router --region=us-central1 --format="table(result.bgp_peer_status[].(peer_ip_address, state))"'

# Step 4: Once Interconnect is primary route again, test failover into VPN
# Disconnect Interconnect (test) and verify automatic failover

# Step 5: Reconnect and verify final state
gcloud compute routers describe nexusshield-onprem-primary-router \
  --region=us-central1 \
  --format="yaml(bgp.peers[])"
```

---

## Monitoring and Alerts

### Key Metrics

```bash
# 1. Interconnect Attachment Status
Metric: compute.googleapis.com/interconnect_attachment/operational_status
Threshold: Should be 1 (UP)
Alert: If status < 1 for 5 minutes

# 2. VPN Tunnel Status
Metric: compute.googleapis.com/vpn_tunnel/tunnel_up
Threshold: Should be 1 (UP)
Alert: If status < 1 for 5 minutes (both tunnels)

# 3. BGP Session Status
Metric: compute.googleapis.com/router/bgp_peer_status
Expected: established (1)
Alert: If BgpSessionState != established

# 4. SSH Certificate Validity
Check: Last rotation timestamp in Vault audit log
Alert: If not rotated in last 35 days (before 30-day expiry)

# 5. Network Throughput
Metric: compute.googleapis.com/interconnect_attachment/sent_bytes_count
Alert: If throughput exceeds expected baseline by 2x
```

### Create Alert Policies

```bash
# Alert for Interconnect down
gcloud alpha monitoring policies create \
  --notification-channels=CHANNEL_ID \
  --display-name="On-Prem Interconnect Down" \
  --condition-display-name="Primary Interconnect status down" \
  --condition-expression='resource.type="compute.googleapis.com/InterconnectAttachment" AND metric.type="compute.googleapis.com/interconnect_attachment/operational_status" AND resource.labels.name=~".*primary-interconnect" AND metric.value < 1'

# Alert for both VPN tunnels down
gcloud alpha monitoring policies create \
  --notification-channels=CHANNEL_ID \
  --display-name="VPN Failover Tunnels Down" \
  --condition-display-name="Both VPN tunnels inactive" \
  --condition-expression='resource.type="compute.googleapis.com/VpnTunnel" AND metric.type="compute.googleapis.com/vpn_tunnel/tunnel_up" AND resource.labels.name=~".*backup-vpn" AND metric.value < 1'
```

### View Logs

```bash
# Check Interconnect events
gcloud logging read "resource.type=gce_network AND protoPayload.resourceName:interconnect" \
  --limit 20 \
  --format=json | jq '.[] | {timestamp: .timestamp, severity: .severity, message: .protoPayload.status}'

# Check VPN tunnel events
gcloud logging read "resource.type=gce_network AND protoPayload.resourceName:vpn_tunnel" \
  --limit 20 \
  --format=json

# Check BGP events
gcloud logging read "resource.type=gce_network_route AND protoPayload.methodName:get_status" \
  --limit 20 \
  --format=json
```

---

## Troubleshooting

### Problem: BGP Routes Not Converging

**Symptoms:** Traffic not routing through backup VPN after Interconnect failure

**Cause:** BGP timers not configured optimally

**Solution:**

```bash
# Check BGP timers
gcloud compute routers describe nexusshield-onprem-backup-router \
  --region=us-east1 \
  --format="yaml(bgp.keepalive_interval_sec, bgp.advertise_intervals[])"

# Update BGP keepalive (if needed)
gcloud compute routers update nexusshield-onprem-backup-router \
  --region=us-east1 \
  --asn=64512 \
  --advertised-groups=ALL_SUBNETS \
  --advertised-routes=10.40.0.0/16
```

### Problem: SSH Certificate Expired

**Symptoms:** SSH access denied with "permission denied (publickey)" or "certificate has expired"

**Cause:** 30-day certificate validity period exceeded

**Solution:**

```bash
# Check certificate validity  
ssh-keygen -L -f ~/.ssh/id_rsa-vault.pub | grep "Valid"

# Request new certificate
vault write -field=signed_key ssh/issue/onprem-deployer \
  username=ubuntu \
  ip_addresses=10.40.1.100 > ~/.ssh/id_rsa-vault-new.pub

# Update SSH config
cp ~/.ssh/id_rsa-vault-new.pub ~/.ssh/id_rsa-vault.pub

# Retry SSH connection
ssh -i ~/.ssh/id_rsa-vault.pub ubuntu@10.40.1.100
```

### Problem: VPN Tunnel Not Connecting

**Symptoms:** VPN tunnel status shows "FIRST_HANDSHAKE" or "DOWN"

**Cause:** IKEv2 negotiation failure, firewall rules, or shared secret mismatch

**Solution:**

```bash
# Verify firewall rules allow IKE and ESP traffic
gcloud compute firewall-rules list --filter="name:nexusshield*"

# Check VPN tunnel details
gcloud compute vpn-tunnels describe nexusshield-backup-vpn-tunnel-1 \
  --region=us-east1 \
  --format="yaml()"

# Verify shared secret is identical on both ends
terraform output vpn_shared_secret  # GCP side secret

# On-premises side: verify /etc/strongswan/ipsec.conf matches

# Restart VPN on on-premises side (if needed)
sudo systemctl restart strongswan

# Check IKE logs on on-premises side
sudo ipsec statusall
```

### Problem: Intercontinect Events Not Triggering Alerts

**Cause:** Notification channel not configured or alert policy disabled

**Solution:**

```bash
# List notification channels
gcloud alpha monitoring notification-channels list

# Create notification channel (if missing)
gcloud alpha monitoring channels create \
  --display-name="ops-email" \
  --type=email \
  --channel-labels="email_address=ops@nexusshield.cloud"

# Get channel ID
CHANNEL_ID=$(gcloud alpha monitoring channels list \
  --filter="displayName:ops-email" \
  --format="value(name)")

# Update alert policy with channel
gcloud alpha monitoring policies update POLICY_ID \
  --notification-channels=$CHANNEL_ID
```

---

## Runbook Index

### Quick Commands Reference

| Task | Command | Purpose |
|------|---------|---------|
| Check Interconnect | `gcloud compute interconnects-attachments describe` | Verify primary connection |
| Check VPN tunnels | `gcloud compute vpn-tunnels list` | Verify backup tunnels |
| Get BGP status | `gcloud compute routers get-status` | Monitor BGP routing |
| Get SSH cert | `vault write ssh/issue/onprem-deployer` | Request new SSH access |
| View audit log | `gcloud logging read "resource.type=..."` | Check network events |
| Failover test | `terraform apply -var=enable_primary=false` | Manual failover drill |

### On-Premises Configuration

| Parameter | Value | Notes |
|-----------|-------|-------|
| Primary ASN | 65000 | BGP ASN for primary on-prem gateway |
| Secondary ASN | 65001 | BGP ASN for secondary on-prem gateway |
| GCP ASN | 64512 | BGP ASN for GCP routers |
| Primary CIDR | 10.40.0.0/16 | On-premises network range |
| Interconnect Region | us-central1 | Primary connection location |
| Backup VPN Region | us-east1 | Failover connection location |
| SSH Key TTL | 30 days | Vault certificate lifetime |

### Related Documentation

- [Google Cloud Interconnect Guide](https://cloud.google.com/docs/guides/ipsec-vpn)
- [BGP Best Practices](https://cloud.google.com/docs/guides/bgp)
- [HashiCorp Vault SSH Documentation](https://www.vaultproject.io/docs/secrets/ssh)
- [Cloud Scheduler Documentation](https://cloud.google.com/scheduler/docs)

### Support Contacts

- **Network Team**: network@nexusshield.cloud
- **On-Premises Admin**: onprem-admin@nexusshield.cloud
- **Vault Administration**: vault-admins@nexusshield.cloud
- **Emergency**: Page on-call engineer via PagerDuty

---

**Last Updated:** 2026-03-13  
**Maintained By:** Infrastructure Team  
**Reviewed:** Quarterly
