# Service Account Bootstrap Record

**Date:** 2026-03-15T16:09:20Z  
**Status:** ✅ COMPLETED

## Deployed Service Accounts

| Service Account | Target Host | Source Host | SSH Key |
|---|---|---|---|
| elevatediq-svc-worker-dev | 192.168.168.42 | 192.168.168.31 | /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-dev/id_ed25519 |
| elevatediq-svc-worker-nas | 192.168.168.42 | 192.168.168.39 | /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-nas/id_ed25519 |
| elevatediq-svc-dev-nas | 192.168.168.39 | 192.168.168.31 | /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-dev-nas/id_ed25519 |

## SSH Configuration

All accounts configured with:
- **Algorithm:** Ed25519 (256-bit)
- **Authentication:** Key-only (PasswordAuthentication=no)
- **Batch Mode:** Enabled (SSH_ASKPASS=none)
- **Permissions:** 600 on private keys, 700 on .ssh directory

## Next Steps

1. Run stress tests using service account auth:
   ```bash
   ssh -i /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-dev-nas/id_ed25519 \
       elevatediq-svc-dev-nas@192.168.168.39 "bash scripts/nas-integration/stress-test-nas.sh --aggressive"
   ```

2. Run NexusShield deployments:
   ```bash
   ssh -i /home/akushnir/self-hosted-runner/secrets/ssh/elevatediq-svc-worker-dev/id_ed25519 \
       elevatediq-svc-worker-dev@192.168.168.42 "sudo systemctl start nexusshield-deploy"
   ```

3. Validate automation:
   ```bash
   # All future SSH will use key-only auth (no passwords required)
   export SSH_ASKPASS=none SSH_ASKPASS_REQUIRE=never DISPLAY=""
   ```

## Log File

Full bootstrap log: /home/akushnir/self-hosted-runner/logs/bootstrap/bootstrap-pwd-fallback-2026-03-15T16:09:20Z.log
